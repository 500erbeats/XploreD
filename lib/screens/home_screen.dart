import 'dart:async';
import 'dart:io' show Platform, Directory;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http_cache_file_store/http_cache_file_store.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';

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
import 'package:screen_brightness/screen_brightness.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'places_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final _mapController = MapController();
  late final AnimatedMapController _animated = AnimatedMapController(
    vsync: this,
    mapController: _mapController,
  );
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

  static const int _detailMinZoom = 14;   // ab hier Einzelzellen
  static const double _cellMeters = 150;  // Zellgröße (Geohash 7)
  final double _urbanRadius = 100;
  final double _ruralRadius = 300;

  CachedTileProvider? _tileProvider;
  AchievementToastQueue? _toastQueue;
  Timer? _viewportDebounce;
  LatLngBounds? _loadedBounds;
  StreamSubscription<ExploredCell>? _cellSub;
  StreamSubscription? _positionSub;
  double? _activeDistanceFilter;
  double? _loadedBucketDeg; // null = Einzelzellen
  double? _aggRadius;       // Zeichenradius im zusammengefassten Modus
  bool _autoRecenterPaused = false;
  bool _followMode = false;
  StreamSubscription<AccelerometerEvent>? _orientationSub;
  bool _saverOn = false;
  bool _saverEnabled = false;
  double _initialZoom = 13;
  double? _lastSavedZoom;
  Timer? _zoomSaveTimer;
  List<List<LatLng>> _highlightRings = const [];
  String? _highlightPlaceName;
  int _todayCount = 0;
  Timer? _todayDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applyScreenSaverSetting();
    _bootstrap();
  }

  void _startOrientationListener() {
    _orientationSub?.cancel();
    _orientationSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen((e) {
      // Hysterese: einschalten bei y < -7, ausschalten erst bei y > -4
      // -> kein Flackern an der Schwelle.
      // Handy kopfüber (Oberkante zeigt nach unten): y negativ.
      // Alternativ "Display nach unten auf den Tisch": e.z statt e.y nehmen.
      final upsideDown = _saverOn ? e.y < -4 : e.y < -7;
      _setSaver(upsideDown);
    });
  }

  Future<void> _setSaver(bool on) async {
    if (on == _saverOn || !mounted) return;
    setState(() => _saverOn = on);
    try {
      if (on) {
        await ScreenBrightness().setApplicationScreenBrightness(0.0);
      } else {
        await ScreenBrightness().resetApplicationScreenBrightness();
      }
    } catch (e) {
      debugPrint('Helligkeit konnte nicht gesetzt werden: $e');
    }
  }

  Future<void> _applyScreenSaverSetting() async {
    _saverEnabled = await _settings.isScreenSaverEnabled();
    if (_saverEnabled) {
      WakelockPlus.enable();
      _startOrientationListener();
    } else {
      _orientationSub?.cancel();
      _orientationSub = null;
      await _setSaver(false);
      WakelockPlus.disable();
    }
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
  if (_saverEnabled) _startOrientationListener();
    _handleResumed();
  } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
    _exploration.setForeground(false);
    _orientationSub?.cancel();
    _orientationSub = null;
    _setSaver(false);
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
    await _refreshTodayCount();
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
    _initialZoom = ((await _settings.getMapZoom()) ?? 13).clamp(9.0, 19.0).toDouble();
    _lastSavedZoom = _initialZoom;

    final onboardingDone = await _settings.isOnboardingCompleted();
    if (!onboardingDone) {
      await _refreshTodayCount();
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
  _activeDistanceFilter = distanceFilter;

  if (Platform.isAndroid) {
    await _startAndroidForegroundTracking(distanceFilter);
  } else {
    _exploration.startListening(distanceFilterMeters: distanceFilter);
  }

  _cellSub?.cancel();
  _cellSub = _exploration.onNewCellExplored.listen(_onNewCellExplored);

  _positionSub?.cancel();
  _positionSub = LocationService.instance.positionStream.listen((position) {
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
      _scheduleTodayRefresh();
      _loadViewportCells();
      _checkAchievementsAfterBackgroundUpdate();
    }
  }

  Future<void> _checkAchievementsAfterBackgroundUpdate() async {
    final stats = await _exploration.getStats();
    await _exploration.achievements.checkAll(stats);
  }

  void _onNewCellExplored(ExploredCell cell) {
    _scheduleTodayRefresh();
    if (_loadedBucketDeg != null) return;
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
  final camera = _mapController.camera;
  final bounds = camera.visibleBounds;
  final latPad = (bounds.north - bounds.south) * 0.5;
  final lngPad = (bounds.east - bounds.west) * 0.5;

  final paddedBounds = LatLngBounds(
    LatLng(bounds.south - latPad, bounds.west - lngPad),
    LatLng(bounds.north + latPad, bounds.east + lngPad),
  );

  // Detailgrad pro ganzer Zoomstufe, damit nicht bei jedem Frame neu
  // geladen wird. Rasterfeld ~10 px groß (Meter pro Pixel bei ~48° Breite).
final level = camera.zoom.floor();
double? bucketDeg;
double? aggRadius;
if (level < _detailMinZoom) {
  final metersPerPixel = 104750 / math.pow(2, level);
  // Rasterfeld: mindestens 2 Zellen breit, mit jedem Rauszoomen größer
  // (~12 Pixel auf dem Bildschirm).
  final bucketMeters = math.max(12 * metersPerPixel, 2 * _cellMeters);
  bucketDeg = bucketMeters / 111320;
  aggRadius = bucketMeters * 0.75;
}

  if (_loadedBounds != null &&
      _loadedBounds!.containsBounds(paddedBounds) &&
      _loadedBucketDeg == bucketDeg) {
    return;
  }

  final cells = bucketDeg == null
      ? await StorageService.instance.getCellsInBounds(
          minLat: paddedBounds.south,
          maxLat: paddedBounds.north,
          minLng: paddedBounds.west,
          maxLng: paddedBounds.east,
        )
      : await StorageService.instance.getCellsInBoundsAggregated(
          minLat: paddedBounds.south,
          maxLat: paddedBounds.north,
          minLng: paddedBounds.west,
          maxLng: paddedBounds.east,
          bucketDeg: bucketDeg,
        );

  if (!mounted) return;
  setState(() {
    _cells = cells;
    _loadedBounds = paddedBounds;
    _loadedBucketDeg = bucketDeg;
    _aggRadius = aggRadius;
  });
}

  /// Rückt die Karte nach, sobald der Standort zu nah an den Bildschirmrand
  /// kommt - kein starres Mitziehen, pausiert bei manuellem Scrollen.
 void _recenterIfNearEdge() {
  final pos = _currentPosition;
  if (pos == null || _outsideRegion || !mounted) return;

  // Follow-Modus: Standort immer exakt in der Bildmitte.
// Follow-Modus:
if (_followMode) {
  _animated.animateTo(
    dest: pos,
    duration: const Duration(milliseconds: 900),
    curve: Curves.linear,
  );
  return;
}

  if (_autoRecenterPaused) return;

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
      _animated.animateTo(dest: pos);
    }
  }

void _onMapEvent(MapEvent event) {
  _scheduleViewportLoad();
  if (event.source != MapEventSource.mapController) {
    _autoRecenterPaused = true;
  }
  // Mit dem Finger verschieben beendet den Follow-Modus.
  if (_followMode &&
      (event.source == MapEventSource.dragStart ||
          event.source == MapEventSource.onDrag)) {
    setState(() => _followMode = false);
  }
  _zoomSaveTimer?.cancel();
  _zoomSaveTimer = Timer(const Duration(seconds: 1), () {
    final zoom = _mapController.camera.zoom;
    if (zoom != _lastSavedZoom) {
      _lastSavedZoom = zoom;
      _settings.setMapZoom(zoom);
    }
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
    _animated.animateTo(dest: pos);
  }

  Future<void> _showAllExplored() async {
    try {
      final b = await StorageService.instance.getExploredBounds();
      if (!mounted) return;
      if (b == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Noch nichts erkundet.')),
        );
        return;
      }
      final (south, north, west, east) = b;
      debugPrint('Alles anzeigen: S$south N$north W$west O$east');

      final fitted = CameraFit.bounds(
        bounds: LatLngBounds(LatLng(south, west), LatLng(north, east)),
        padding: const EdgeInsets.all(48),
        maxZoom: 16,
      ).fit(_mapController.camera);
      debugPrint('Ziel: ${fitted.center}, Zoom ${fitted.zoom}');

      setState(() => _followMode = false);
      _autoRecenterPaused = true;
      _mapController.move(fitted.center, fitted.zoom);
    } catch (e, st) {
      debugPrint('Alles anzeigen fehlgeschlagen: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Konnte nicht zoomen: $e')),
        );
      }
    }
  }

Future<void> _openPlaces() async {
  final placeId = await Navigator.push<String>(
    context,
    MaterialPageRoute(builder: (_) => const PlacesScreen()),
  );
  if (placeId != null) _showPlace(placeId);
}

void _showPlace(String placeId) {
  final bounds = BoundaryService.instance.boundsFor(placeId);
  final rings = BoundaryService.instance.ringsFor(placeId);
  if (bounds == null || rings.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Für diesen Ort liegen keine Grenzdaten vor.')),
    );
    return;
  }
  final name = RegionService.instance.config.places
      .firstWhere((p) => p.id == placeId)
      .name;
  setState(() {
    _followMode = false;
    _highlightRings = rings;
    _highlightPlaceName = name;
  });
  _autoRecenterPaused = true;
  _mapController.fitCamera(
    CameraFit.bounds(
      bounds: bounds,
      padding: const EdgeInsets.all(48),
      maxZoom: 15,
    ),
  );
}

Future<void> _refreshTodayCount() async {
  final now = DateTime.now();
  final count = await StorageService.instance
      .getExploredCellCountSince(DateTime(now.year, now.month, now.day));
  if (mounted && count != _todayCount) setState(() => _todayCount = count);
}

void _scheduleTodayRefresh() {
  _todayDebounce?.cancel();
  _todayDebounce = Timer(const Duration(milliseconds: 500), _refreshTodayCount);
}

void _toggleFollowMode() {
  if (_followMode) {
    setState(() => _followMode = false);
    return;
  }
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
  setState(() => _followMode = true);
  _autoRecenterPaused = false;
  _mapController.move(pos, _mapController.camera.zoom);
}

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _viewportDebounce?.cancel();
    _cellSub?.cancel();
    _positionSub?.cancel();
    _orientationSub?.cancel();
    _todayDebounce?.cancel();
    WakelockPlus.disable();
    ScreenBrightness().resetApplicationScreenBrightness();
    if (Platform.isAndroid) {
      FlutterForegroundTask.removeTaskDataCallback(_onBackgroundData);
    } else {
      _exploration.stopListening();
    }
    _exploration.dispose();
    _zoomSaveTimer?.cancel();
    _animated.dispose();
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
              initialZoom: _initialZoom,
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
                      urbanRadiusMeters: math.max(_urbanRadius, _aggRadius ?? 0),
                      ruralRadiusMeters: math.max(_ruralRadius, _aggRadius ?? 0),
                      fogColor: isDarkTheme
                          ? const Color(0xE6F0F0F5)
                          : const Color(0xCC0A0E1A),
                    ),
                  ),
                ),
              ),
              if (_highlightRings.isNotEmpty)
              PolygonLayer(
                polygons: [
                  for (final ring in _highlightRings)
                    Polygon(
                      points: ring,
                      borderColor: Colors.orangeAccent,
                      borderStrokeWidth: 3,
                    ),
                ],
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
            todayAreaKm2: _todayCount * 0.15 * 0.15,
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
                  onTap: () async {
                    final changed = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(builder: (_) => const PrivacyScreen()),
                    );
                    if (changed == true) await _handleResumed();
                  },
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
                  await _applyScreenSaverSetting();
                  final newFilter = await _settings.getDistanceFilterMeters();
                  if (_tracking && newFilter != _activeDistanceFilter) {
                    await _handleTrackingToggle(false);
                    await _handleTrackingToggle(true);
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
            if (_highlightRings.isNotEmpty)
            Positioned(
              left: 16,
              right: 88,
              bottom: 96,
              child: Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  backgroundColor: Colors.black.withValues(alpha: 0.75),
                  labelStyle: const TextStyle(color: Colors.white),
                  deleteIconColor: Colors.white,
                  avatar: const Icon(Icons.border_outer, size: 18, color: Colors.orangeAccent),
                  label: Text('Ortsgrenze: $_highlightPlaceName'),
                  onDeleted: () => setState(() {
                    _highlightRings = const [];
                    _highlightPlaceName = null;
                  }),
                ),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 32,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'places',
                    tooltip: 'Orte',
                    onPressed: _openPlaces,
                    child: const Icon(Icons.format_list_bulleted),
                  ),
                  const SizedBox(height: 12),
                  FloatingActionButton.small(
                    heroTag: 'fit-all',
                    tooltip: 'Alles Erkundete anzeigen',
                    onPressed: _showAllExplored,
                    child: const Icon(Icons.zoom_out_map),
                  ),
                  const SizedBox(height: 12),
                  FloatingActionButton.small(
                    heroTag: 'follow',
                    backgroundColor: _followMode ? Colors.blueAccent : null,
                    foregroundColor: _followMode ? Colors.white : null,
                    onPressed: _toggleFollowMode,
                    child: Icon(_followMode ? Icons.navigation : Icons.navigation_outlined),
                  ),
                  const SizedBox(height: 16),
                  FloatingActionButton(
                    heroTag: 'center',
                    onPressed: _centerOnMyLocation,
                    child: const Icon(Icons.my_location),
                  ),
                ],
              ),
            ),
          if (_saverOn)
          const Positioned.fill(
            child: AbsorbPointer(
              child: ColoredBox(color: Colors.black),
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
  final double todayAreaKm2;

  const _StatsBadge({
    required this.exploredCount,
    required this.areaKm2,
    required this.tracking,
    this.placeName,
    required this.todayAreaKm2,
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
            if (true) // (todayAreaKm2 > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '+${todayAreaKm2.toStringAsFixed(2)} km² heute',
                style: const TextStyle(color: Colors.greenAccent, fontSize: 11),
              ),
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