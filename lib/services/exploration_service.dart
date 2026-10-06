import 'dart:async';
import 'package:dart_geohash/dart_geohash.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/achievement.dart';
import '../models/explored_cell.dart';
import '../models/place.dart';
import 'achievement_service.dart';
import 'boundary_service.dart';
import 'location_service.dart';
import 'place_achievement_service.dart';
import 'settings_service.dart';
import 'storage_service.dart';

class ExplorationService {
  static const int _geohashPrecision = 7;
  static const double _maxGapMeters = 15000;
  static const double _interpolationStepMeters = 200;

  final _newCellController = StreamController<ExploredCell>.broadcast();
  Stream<ExploredCell> get onNewCellExplored => _newCellController.stream;

  final achievements = AchievementService();
  Stream<AchievementDefinition> get onAchievementUnlocked => achievements.onUnlocked;

  final placeAchievements = PlaceAchievementService();
  Stream<AchievementDefinition> get onPlaceAchievementUnlocked => placeAchievements.onUnlocked;

  int _totalExploredCount = 0;
  int get totalExploredCount => _totalExploredCount;

  bool _inForeground = true;
  void setForeground(bool value) => _inForeground = value;

  Future<void> init() async {
  _totalExploredCount = await StorageService.instance.getExploredCellCount();
  try {
    await BoundaryService.instance.load();
  } catch (e) {
    debugPrint('Grenzdaten konnten nicht geladen werden: $e');
  }
  await placeAchievements.init();
  await _backfillMissingPlaceIds(); // NEU
}

/// Einmaliger Nachtrag: berechnet place_id für alle Zellen, die noch NULL
/// haben. Läuft nur einmal, danach per Flag übersprungen.
Future<void> _backfillMissingPlaceIds() async {
  final settings = SettingsService();
  final done = await settings.isPlaceIdBackfillDone();
  if (done) return;

  final cells = await StorageService.instance.getCellsWithoutPlaceId();
  debugPrint('Backfill: ${cells.length} Zellen ohne place_id gefunden');

  for (final cell in cells) {
    final place = BoundaryService.instance.placeContaining(cell.centerLat, cell.centerLng);
    await StorageService.instance.updateCellPlaceId(cell.geohash, place?.id);
  }

  await settings.setPlaceIdBackfillDone(true);
  debugPrint('Backfill abgeschlossen');
}

  void startListening() {
    LocationService.instance.startTracking(onPosition: _handlePosition);
  }

  void stopListening() {
    LocationService.instance.stopTracking();
  }

  Future<void> _handlePosition(Position position) async {
    final lat = position.latitude;
    final lng = position.longitude;

    if (_inForeground) {
      await recordVisit(lat, lng);
    } else {
      // Im Hintergrund nur protokollieren, Verarbeitung erst beim Zurückkehren.
      await StorageService.instance.logRawPoint(lat, lng, DateTime.now());
    }
  }

  Future<void> replayQueuedTrack() async {
    final queued = await StorageService.instance.getQueuedTrackPoints();
    if (queued.isEmpty) return;

    for (final point in queued) {
      await recordVisit(point.lat, point.lng);
    }
    await StorageService.instance.clearTrackPoints(queued.map((p) => p.id).toList());
  }

  /// Zentrale Methode. Außerhalb des Spielgebiets passiert bewusst nichts.
Future<void> recordVisit(double lat, double lng) async {
    final start = DateTime.now();
    debugPrint('recordVisit START $start: $lat, $lng');    if (!isInsideRegion(lat, lng)) return;

    final last = await StorageService.instance.getLastPosition();

    await _processPoint(lat, lng, isInterpolated: false);
    if (last != null) {
      await _fillGap(last.$1, last.$2, lat, lng);
      await _trackDistance(last.$1, last.$2, lat, lng);
    }

    await StorageService.instance.recordExplorationDay(DateTime.now());
    await StorageService.instance.saveLastPosition(lat, lng);

    final stats = await getStats();
    await achievements.checkAll(stats);
    await placeAchievements.checkPlaceAt(lat, lng);
    debugPrint('recordVisit ENDE ${DateTime.now()}: $lat, $lng');
  }

  /// [isInterpolated] = true für Lückenfüll-Punkte: deckt NUR die eigene
  /// Zelle auf, keine Nachbarn - echte GPS-Fixes decken weiterhin den vollen
  /// 3x3-Block auf. Verhindert, dass nachträglich aufgefüllte Strecken
  /// deutlich breiter wirken als live erkundete.
Future<void> _processPoint(double lat, double lng, {required bool isInterpolated}) async {
  await _revealCells(lat, lng, includeNeighbors: !isInterpolated);
}

Future<void> _fillGap(double lat1, double lng1, double lat2, double lng2) async {
  final gap = Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
  debugPrint('GPS-Lücke: ${gap.round()} m'); // NEU - zum Beobachten

  if (gap < _interpolationStepMeters * 1.5 || gap > _maxGapMeters) {
    if (gap > _maxGapMeters) {
      debugPrint('Lücke zu groß (> $_maxGapMeters m), übersprungen'); // NEU
    }
    return;
  }

  final steps = (gap / _interpolationStepMeters).floor();
  for (var i = 1; i < steps; i++) {
    final t = i / steps;
    final lat = lat1 + (lat2 - lat1) * t;
    final lng = lng1 + (lng2 - lng1) * t;
    if (!isInsideRegion(lat, lng)) continue;
    await _processPoint(lat, lng, isInterpolated: true);
  }
}

  Future<void> _revealCells(double lat, double lng, {required bool includeNeighbors}) async {
  final geoHasher = GeoHasher();
  final centerHash = geoHasher.encode(lng, lat, precision: _geohashPrecision);
  final hashes = includeNeighbors
      ? [centerHash, ...geoHasher.neighbors(centerHash).values]
      : [centerHash];

  for (final hash in hashes) {
    final decoded = geoHasher.decode(hash);
    final cellLat = decoded[1];
    final cellLng = decoded[0];
    final place = BoundaryService.instance.placeContaining(cellLat, cellLng);

    final cell = ExploredCell(
      geohash: hash,
      centerLat: cellLat,
      centerLng: cellLng,
      firstVisited: DateTime.now(),
      placeId: place?.id,
    );
    final isNew = await StorageService.instance.addExploredCell(cell);
    if (isNew) {
      _totalExploredCount++;
      _newCellController.add(cell);
    }

    // NEU: Sobald irgendeine Zelle einem Ort zugeordnet wird, gilt er als
    // besucht - genau dieselbe Regel, die auch die Flächen-Prozentzahl
    // bestimmt. Vorher lief "besucht" nur über den exakten GPS-Punkt
    // (_processPoint), was strenger war als die Flächenzählung.
    if (place != null) await placeAchievements.registerVisit(place);
  }
}

  Future<void> _trackDistance(double lastLat, double lastLng, double lat, double lng) async {
    final meters = Geolocator.distanceBetween(lastLat, lastLng, lat, lng);
    if (meters > 0 && meters < _maxGapMeters) {
      await StorageService.instance.addDistanceMeters(meters);
    }
  }

  double get estimatedExploredAreaKm2 {
    const cellAreaKm2 = 0.15 * 0.15;
    return _totalExploredCount * cellAreaKm2;
  }

  Future<StatsSnapshot> getStats() async {
    final cellCount = await StorageService.instance.getExploredCellCount();
    final distanceM = await StorageService.instance.getTotalDistanceMeters();
    final dayCount = await StorageService.instance.getExplorationDayCount();
    final days = await StorageService.instance.getExplorationDaysSorted();
    final (current, longest) = _computeStreaks(days);

    return StatsSnapshot(
      exploredCells: cellCount,
      areaKm2: cellCount * 0.15 * 0.15,
      distanceKm: distanceM / 1000,
      explorationDays: dayCount,
      currentStreak: current,
      longestStreak: longest,
    );
  }

  (int, int) _computeStreaks(List<DateTime> sortedDays) {
    if (sortedDays.isEmpty) return (0, 0);

    int longest = 1;
    int running = 1;
    for (var i = 1; i < sortedDays.length; i++) {
      final gap = sortedDays[i].difference(sortedDays[i - 1]).inDays;
      if (gap == 1) {
        running++;
        longest = running > longest ? running : longest;
      } else if (gap > 1) {
        running = 1;
      }
    }

    final today = DateTime.now();
    final todayKey = DateTime(today.year, today.month, today.day);
    final gapToToday = todayKey.difference(sortedDays.last).inDays;
    final current = gapToToday <= 1 ? running : 0;

    return (current, longest);
  }

  void dispose() {
    _newCellController.close();
    achievements.dispose();
    placeAchievements.dispose();
  }
}