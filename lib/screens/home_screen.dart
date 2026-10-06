import 'dart:async';
import 'dart:io' show Platform, Directory;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http_cache_file_store/http_cache_file_store.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';

import '../models/explored_cell.dart';
import '../models/place.dart';
import '../services/background_task_handler.dart';
import '../services/boundary_service.dart';
import '../services/exploration_service.dart';
import '../services/location_service.dart';
import '../services/region_service.dart';
import '../services/settings_service.dart';
import '../services/storage_service.dart';
import '../widgets/achievement_toast.dart';
import '../widgets/fog_overlay_painter.dart';
import 'onboarding_screen.dart';
import 'privacy_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _mapController = MapController();
  final _exploration = ExplorationService();
  final _settings = SettingsService();

  List<ExploredCell> _cells = [];
  LatLng? _currentPosition;
  bool _tracking = false;
  bool _loading = true;
  bool _outsideRegion = false;
  String? _currentPlaceName;
  String _mapTheme = 'light';
  String? _cartoApiKey;

  final double _urbanRadius = 100;
  final double _ruralRadius = 300;

  CachedTileProvider? _tileProvider;
  AchievementToastQueue? _toastQueue;
  Timer? _viewportDebounce;
  LatLngBounds? _loadedBounds;
  bool _autoRecenterPaused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _toastQueue ??= AchievementToastQueue(Overlay.of(context));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _exploration.setForeground(true);
      _handleResumed();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _exploration.setForeground(false);
    }
  }

  Future<void> _handleResumed() async {
    if (_loading || !mounted) return;
    await _exploration.replayQueuedTrack();
    await _exploration.init();
    _loadedBounds = null;
    try {
      await _loadViewportCells();
    } catch (e) {
      debugPrint('Refresh nach Resume übersprungen: $e');
    }
    if (mounted) setState(() {});
  }

  Future<void> _initTileProvider() async {
    final cacheDir = await getTemporaryDirectory();
    final cachePath = '${cacheDir.path}/map_tiles';
    await Directory(cachePath).create(recursive: true);

    _tileProvider = CachedTileProvider(
      maxStale: const Duration(days: 30),
      store: FileCacheStore(cachePath),
    );
  }

  Future<void> _bootstrap() async {
    await _initTileProvider();
    await _exploration.init();

    _exploration.onAchievementUnlocked.listen((definition) {
      HapticFeedback.mediumImpact();
      _toastQueue?.show(definition);
    });
    _exploration.onPlaceAchievementUnlocked.listen((definition) {
      HapticFeedback.mediumImpact();
      _toastQueue?.show(definition);
    });

    final last = await StorageService.instance.getLastPosition();
    if (last != null) {
      _currentPosition = LatLng(last.$1, last.$2);
      _outsideRegion = !isInsideRegion(last.$1, last.$2);
      _currentPlaceName = BoundaryService.instance.placeContaining(last.$1, last.$2)?.name;
    }
    _mapTheme = await _settings.getMapTheme();
    _cartoApiKey = await _settings.getCartoApiKey();

    final onboardingDone = await _settings.isOnboardingCompleted();
    if (!onboardingDone) {
      setState(() => _loading = false);
      return;
    }

    final trackingEnabled = await _settings.isBackgroundTrackingEnabled();
    final permissionResult = await LocationService.instance.checkCurrentStatus();
    if (!mounted) return;

    if (permissionResult == LocationPermissionResult.deniedForever) {
      _showPermissionDeniedDialog();
    } else if (trackingEnabled) {
      await _startTracking();
    }

    setState(() => _loading = false);
  }

  Future<void> _onOnboardingFinished() async {
    setState(() => _loading = true);

    final trackingEnabled = await _settings.isBackgroundTrackingEnabled();
    final permissionResult = await LocationService.instance.checkCurrentStatus();
    if (!mounted) return;

    if (permissionResult != LocationPermissionResult.deniedForever && trackingEnabled) {
      await _startTracking();
    }

    setState(() => _loading = false);
  }

  Future<void> _startTracking() async {
    final distanceFilter = await _settings.getDistanceFilterMeters();

    if (Platform.isAndroid) {
      await _startAndroidForegroundTracking(distanceFilter);
    } else {
      _exploration.startListening();
    }

    _exploration.onNewCellExplored.listen(_onNewCellExplored);

    LocationService.instance.positionStream.listen((position) {
      if (!mounted) return;
      final lat = position.latitude;
      final lng = position.longitude;
      setState(() {
        _currentPosition = LatLng(lat, lng);
        _outsideRegion = !isInsideRegion(lat, lng);
        _currentPlaceName = BoundaryService.instance.placeContaining(lat, lng)?.name;
      });
      _recenterIfNearEdge();
    });

    setState(() => _tracking = true);
  }

  Future<void> _startAndroidForegroundTracking(double distanceFilter) async {
    final notificationPermission = await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }

    FlutterForegroundTask.addTaskDataCallback(_onBackgroundData);

    try {
      final result = await FlutterForegroundTask.startService(
        notificationTitle: 'XploreD',
        notificationText: 'Erkundung läuft im Hintergrund',
        callback: startCallback,
      );
      debugPrint('Foreground service start result: $result');
    } catch (e, stack) {
      debugPrint('FEHLER beim Starten des Foreground Service: $e');
      debugPrint('$stack');
    }
  }

  Future<void> _handleTrackingToggle(bool enabled) async {
    if (enabled) {
      await _startTracking();
    } else {
      if (Platform.isAndroid) {
        FlutterForegroundTask.removeTaskDataCallback(_onBackgroundData);
        await FlutterForegroundTask.stopService();
      } else {
        _exploration.stopListening();
      }
      setState(() => _tracking = false);
    }
  }

  void _onBackgroundData(Object data) {
    if (data is Map) {
      final lat = data['lat'] as double?;
      final lng = data['lng'] as double?;
      if (lat != null && lng != null && mounted) {
        setState(() {
          _currentPosition = LatLng(lat, lng);
          _outsideRegion = !isInsideRegion(lat, lng);
          _currentPlaceName = BoundaryService.instance.placeContaining(lat, lng)?.name;
        });
        _recenterIfNearEdge();
      }
      _loadViewportCells();
      _checkAchievementsAfterBackgroundUpdate();
    }
  }

  Future<void> _checkAchievementsAfterBackgroundUpdate() async {
    final stats = await _exploration.getStats();
    await _exploration.achievements.checkAll(stats);
  }

  void _onNewCellExplored(ExploredCell cell) {
    final loaded = _loadedBounds;
    if (loaded == null) return;

    final point = LatLng(cell.centerLat, cell.centerLng);
    if (loaded.contains(point)) {
      setState(() => _cells = [..._cells, cell]);
    }
  }

  void _scheduleViewportLoad() {
    _viewportDebounce?.cancel();
    _viewportDebounce = Timer(const Duration(milliseconds: 300), _loadViewportCells);
  }

  Future<void> _loadViewportCells() async {
    final bounds = _mapController.camera.visibleBounds;
    final latPad = (bounds.north - bounds.south) * 0.5;
    final lngPad = (bounds.east - bounds.west) * 0.5;

    final paddedBounds = LatLngBounds(
      LatLng(bounds.south - latPad, bounds.west - lngPad),
      LatLng(bounds.north + latPad, bounds.east + lngPad),
    );

    if (_loadedBounds != null && _loadedBounds!.containsBounds(paddedBounds)) {
      return;
    }

    final cells = await StorageService.instance.getCellsInBounds(
      minLat: paddedBounds.south,
      maxLat: paddedBounds.north,
      minLng: paddedBounds.west,
      maxLng: paddedBounds.east,
    );

    if (!mounted) return;
    setState(() {
      _cells = cells;
      _loadedBounds = paddedBounds;
    });
  }

  /// Rückt die Karte nach, sobald der Standort zu nah an den Bildschirmrand
  /// kommt - kein starres Mitziehen, pausiert bei manuellem Scrollen.
  void _recenterIfNearEdge() {
    if (_autoRecenterPaused) return;
    final pos = _currentPosition;
    if (pos == null || _outsideRegion || !mounted) return;

    final camera = _mapController.camera;
    final screenPoint = camera.latLngToScreenPoint(pos);
    final size = MediaQuery.sizeOf(context);

    const marginFraction = 0.18;
    final marginX = size.width * marginFraction;
    final marginY = size.height * marginFraction;

    final nearEdge = screenPoint.x < marginX ||
        screenPoint.x > size.width - marginX ||
        screenPoint.y < marginY ||
        screenPoint.y > size.height - marginY;

    if (nearEdge) {
      _mapController.move(pos, camera.zoom);
    }
  }

  void _onMapEvent(MapEvent event) {
    _scheduleViewportLoad();
    if (event.source != MapEventSource.mapController) {
      _autoRecenterPaused = true;
    }
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Standortzugriff benötigt'),
        content: const Text(
          'Diese App deckt die Karte basierend auf deinem realen Standort '
          'auf. Ohne Standortzugriff kann nichts erkundet werden. Bitte '
          'aktiviere die Berechtigung in den Systemeinstellungen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Verstanden'),
          ),
        ],
      ),
    );
  }

  void _centerOnMyLocation() {
    final pos = _currentPosition;
    if (pos == null) return;
    if (_outsideRegion) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Du bist gerade außerhalb von ${RegionService.instance.config.displayName}.',
          ),
        ),
      );
      return;
    }
    _autoRecenterPaused = false;
    _mapController.move(pos, _mapController.camera.zoom);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _viewportDebounce?.cancel();
    if (Platform.isAndroid) {
      FlutterForegroundTask.removeTaskDataCallback(_onBackgroundData);
    } else {
      _exploration.stopListening();
    }
    _exploration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return FutureBuilder<bool>(
      future: _settings.isOnboardingCompleted(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.data == false) {
          return OnboardingScreen(onFinished: _onOnboardingFinished);
        }
        return _buildMapScaffold(context);
      },
    );
  }

  Widget _buildMapScaffold(BuildContext context) {
    final region = RegionService.instance.config;
    final pos = _currentPosition;
    final startCenter =
        (pos != null && isInsideRegion(pos.latitude, pos.longitude)) ? pos : region.center;
    final isDarkTheme = _mapTheme == 'dark';
    final hasCartoKey = _cartoApiKey != null && _cartoApiKey!.isNotEmpty;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: startCenter,
              initialZoom: 13,
              minZoom: 9,
              maxZoom: 19,
              cameraConstraint: CameraConstraint.contain(bounds: region.bounds),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onMapEvent: _onMapEvent,
              onMapReady: _loadViewportCells,
            ),
            children: [
              if (hasCartoKey)
                TileLayer(
                  urlTemplate: isDarkTheme
                      ? 'https://basemaps.cartocdn.com/rastertiles/dark_all/{z}/{x}/{y}.png?key=$_cartoApiKey'
                      : 'https://basemaps.cartocdn.com/rastertiles/light_all/{z}/{x}/{y}.png?key=$_cartoApiKey',
                  userAgentPackageName: 'com.example.xplored',
                  tileProvider: _tileProvider,
                ),
              MobileLayerTransformer(
                child: StreamBuilder<MapEvent>(
                  stream: _mapController.mapEventStream,
                  builder: (context, _) => CustomPaint(
                    size: Size.infinite,
                    painter: FogOverlayPainter(
                      exploredCells: _cells,
                      camera: _mapController.camera,
                      urbanRadiusMeters: _urbanRadius,
                      ruralRadiusMeters: _ruralRadius,
                      fogColor: isDarkTheme
                          ? const Color(0xE6F0F0F5)
                          : const Color(0xCC0A0E1A),
                    ),
                  ),
                ),
              ),
              if (_currentPosition != null && !_outsideRegion)
                MarkerLayer(markers: [
                  Marker(
                    point: _currentPosition!,
                    width: 24,
                    height: 24,
                    child: const _CurrentLocationDot(),
                  ),
                ]),
            ],
          ),
          _StatsBadge(
            exploredCount: _exploration.totalExploredCount,
            areaKm2: _exploration.estimatedExploredAreaKm2,
            tracking: _tracking,
            placeName: _currentPlaceName,
          ),
          Positioned(
            top: 56,
            right: 16,
            child: Row(
              children: [
                _NavIconButton(
                  icon: Icons.bar_chart,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => StatsScreen(exploration: _exploration)),
                  ),
                ),
                const SizedBox(width: 8),
                _NavIconButton(
                  icon: Icons.privacy_tip_outlined,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PrivacyScreen()),
                  ),
                ),
                const SizedBox(width: 8),
                _NavIconButton(
                  icon: Icons.settings,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SettingsScreen(onTrackingToggle: _handleTrackingToggle),
                      ),
                    );
                    final newTheme = await _settings.getMapTheme();
                    final newKey = await _settings.getCartoApiKey();
                    if (mounted) {
                      setState(() {
                        _mapTheme = newTheme;
                        _cartoApiKey = newKey;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          if (_outsideRegion)
            Positioned(
              left: 16,
              right: 88,
              bottom: 32,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Du bist außerhalb ${region.displayName} – hier wird nichts aufgedeckt.',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
          if (!hasCartoKey)
            Positioned(
              left: 16,
              right: 16,
              top: 120,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Kein Kartenanbieter konfiguriert',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Trag in den Einstellungen einen kostenlosen CARTO API-Key ein, '
                      'um die Kartenkacheln zu laden.',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            right: 16,
            bottom: 32,
            child: FloatingActionButton(
              heroTag: 'center',
              onPressed: _centerOnMyLocation,
              child: const Icon(Icons.my_location),
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrentLocationDot extends StatelessWidget {
  const _CurrentLocationDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.blueAccent,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.blueAccent.withValues(alpha: 0.5),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
      ),
    );
  }
}

class _StatsBadge extends StatelessWidget {
  final int exploredCount;
  final double areaKm2;
  final bool tracking;
  final String? placeName;

  const _StatsBadge({
    required this.exploredCount,
    required this.areaKm2,
    required this.tracking,
    this.placeName,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 56,
      left: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  tracking ? Icons.gps_fixed : Icons.gps_off,
                  size: 14,
                  color: tracking ? Colors.greenAccent : Colors.grey,
                ),
                const SizedBox(width: 6),
                Text(
                  '${areaKm2.toStringAsFixed(2)} km² erkundet',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            if (placeName != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  placeName!,
                  style: TextStyle(color: Colors.grey[400], fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _NavIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        shape: BoxShape.circle,
      ),
      child: IconButton(icon: Icon(icon, color: Colors.white), onPressed: onTap),
    );
  }
}