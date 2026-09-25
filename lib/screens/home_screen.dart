import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/explored_cell.dart';
import '../services/background_task_handler.dart';
import '../services/exploration_service.dart';
import '../services/location_service.dart';
import '../services/settings_service.dart';
import '../services/storage_service.dart';
import '../widgets/achievement_toast.dart';
import '../widgets/fog_overlay_painter.dart';
import 'onboarding_screen.dart';
import 'privacy_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import '../models/place.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:http_cache_file_store/http_cache_file_store.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _mapController = MapController();
  final _exploration = ExplorationService();
  final _settings = SettingsService();

  List<ExploredCell> _cells = [];
  LatLng? _currentPosition;
  bool _tracking = false;
  bool _loading = true;
final double _urbanRadius = 100;
final double _ruralRadius = 300;

  AchievementToastQueue? _toastQueue;
  Timer? _viewportDebounce;
  LatLngBounds? _loadedBounds;
  CachedTileProvider? _tileProvider;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Braucht den Overlay-Context aus dem Widget-Baum - in initState() noch
    // nicht sicher verfügbar, deshalb hier statt dort.
    _toastQueue ??= AchievementToastQueue(Overlay.of(context));
  }

  Future<void> _bootstrap() async {
  await _initTileProvider(); // NEU - vor allem anderen
  try {
    await _exploration.init();

    _exploration.onAchievementUnlocked.listen((definition) {
      _toastQueue?.show(definition);
    });
    _exploration.onPlaceAchievementUnlocked.listen((definition) {
      _toastQueue?.show(definition);
    });

    final last = await StorageService.instance.getLastPosition();
    if (last != null) {
      _currentPosition = LatLng(last.$1, last.$2);
    }

    final onboardingDone = await _settings.isOnboardingCompleted();
    if (!onboardingDone) {
      // build() zeigt den OnboardingScreen; der Permission-/Tracking-Teil
      // läuft danach über _onOnboardingFinished().
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
  catch (e, stack) {
    debugPrint('FEHLER in _bootstrap: $e');
    debugPrint('$stack');
    if (mounted) setState(() => _loading = false); // Spinner in jedem Fall beenden
  }
}
  
  /// Wird vom OnboardingScreen aufgerufen, sobald der Nutzer ihn durchlaufen
  /// hat - startet danach den normalen Tracking-Pfad.
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
    // Hinweis (offener Punkt): dieser Wert wird aktuell nur für den Android-
    // Foreground-Task-Start geladen, aber noch nicht bis ins tatsächliche
    // GPS-Sampling durchgereicht - siehe Kommentar in LocationService.startTracking().
    final distanceFilter = await _settings.getDistanceFilterMeters();

    if (Platform.isAndroid) {
      await _startAndroidForegroundTracking(distanceFilter);
    } else {
      _exploration.startListening();
    }

    _exploration.onNewCellExplored.listen(_onNewCellExplored);

    LocationService.instance.positionStream.listen((position) {
      if (!mounted) return;
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
      });
    });

    setState(() => _tracking = true);
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

  Future<void> _startAndroidForegroundTracking(double distanceFilter) async {
  final notificationPermission =
      await FlutterForegroundTask.checkNotificationPermission();
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

  /// Wird vom Settings-Screen aufgerufen, wenn der Nutzer den Tracking-
  /// Schalter umlegt.
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
        setState(() => _currentPosition = LatLng(lat, lng));
      }
      // Hintergrund-Updates können neue Zellen weit außerhalb des aktuell
      // sichtbaren Bereichs erzeugen (z.B. nach einer Autofahrt) - hier lohnt
      // sich ein gezielter Reload statt der lokalen Ergänzungslogik unten.
      _loadViewportCells();
      _checkAchievementsAfterBackgroundUpdate();
    }
  }

  /// Der Hintergrund-Isolate (background_task_handler.dart) schaltet
  /// Achievements bereits selbst frei, meldet sie aber nicht an die UI.
  /// unlockAchievement() ist idempotent, ein erneuter Check ist also
  /// gefahrlos möglich.
  Future<void> _checkAchievementsAfterBackgroundUpdate() async {
    final stats = await _exploration.getStats();
    await _exploration.achievements.checkAll(stats);
  }

  /// Ergänzt eine neu erkundete Zelle lokal, wenn sie im aktuell geladenen
  /// Viewport-Bereich liegt - vermeidet einen kompletten Reload bei jeder
  /// einzelnen neuen Zelle.
  void _onNewCellExplored(ExploredCell cell) {
    final loaded = _loadedBounds;
    if (loaded == null) return;

    final point = LatLng(cell.centerLat, cell.centerLng);
    if (loaded.contains(point)) {
      setState(() => _cells = [..._cells, cell]);
    }
  }

  /// Debounced um 300ms, damit während eines Drags/Zooms nicht dutzende
  /// Queries feuern.
  void _scheduleViewportLoad() {
    _viewportDebounce?.cancel();
    _viewportDebounce = Timer(const Duration(milliseconds: 300), _loadViewportCells);
  }

  /// Lädt nur Zellen im sichtbaren Kartenausschnitt plus 50% Randpuffer.
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
    if (_currentPosition != null) {
      _mapController.move(_currentPosition!, _mapController.camera.zoom);
    }
  }

  @override
  void dispose() {
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
    final startCenter = _currentPosition ?? const LatLng(52.5200, 13.4050);
    String? lastTileError;
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: startCenter,
              initialZoom: 13,
              minZoom: 10,
              maxZoom: 19,
              cameraConstraint: CameraConstraint.contain(bounds: markgraeflerlandBounds),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onMapEvent: (event) => _scheduleViewportLoad(),
              onMapReady: _loadViewportCells,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://basemaps.cartocdn.com/rastertiles/dark_all/{z}/{x}/{y}.png?key=cb1_3x3a_1_7df294938ddb840feac965e2',
                userAgentPackageName: 'com.example.xplored',
                tileProvider: _tileProvider,
              ),
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(
                    '© OpenStreetMap contributors © CARTO',
                    onTap: () {},
                  ),
                ],
              ),
             // Fog-of-War-Ebene: reagiert auf Kamera-Änderungen (Pan/Zoom).
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
                  ),
                  ),
                ),
              ),
              if (_currentPosition != null)
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
          ),
          if (lastTileError != null)
            Positioned(
              top: 100,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Tile-Fehler: $lastTileError',
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
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
                    MaterialPageRoute(
                      builder: (_) => StatsScreen(exploration: _exploration),
                    ),
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
                        builder: (_) =>
                            SettingsScreen(onTrackingToggle: _handleTrackingToggle),
                      ),
                    );
                  },
                ),
              ],
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

  const _StatsBadge({
    required this.exploredCount,
    required this.areaKm2,
    required this.tracking,
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
        child: Row(
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
