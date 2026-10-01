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
import 'storage_service.dart';

class ExplorationService {
  static const int _geohashPrecision = 7;

  /// Größte Lücke zwischen zwei Positionen, die noch als "durchgefahren"
  /// gilt (Zellen dazwischen aufdecken + Distanz zählen).
  static const double _maxGapMeters = 3000;

  /// Abstand der Zwischenpunkte beim Lückenfüllen. Jeder Punkt deckt 3x3
  /// Zellen auf, 200 m reichen also ohne Löcher.
  static const double _interpolationStepMeters = 200;

  final _newCellController = StreamController<ExploredCell>.broadcast();
  Stream<ExploredCell> get onNewCellExplored => _newCellController.stream;

  final achievements = AchievementService();
  Stream<AchievementDefinition> get onAchievementUnlocked => achievements.onUnlocked;

  final placeAchievements = PlaceAchievementService();
  Stream<AchievementDefinition> get onPlaceAchievementUnlocked => placeAchievements.onUnlocked;

  int _totalExploredCount = 0;
  int get totalExploredCount => _totalExploredCount;

  Future<void> init() async {
    _totalExploredCount = await StorageService.instance.getExploredCellCount();
    try {
      await BoundaryService.instance.load();
    } catch (e) {
      // Ohne Grenzdaten läuft das Tracking mit der Kreis-Näherung weiter.
      debugPrint('Grenzdaten konnten nicht geladen werden: $e');
    }
    await placeAchievements.init();
  }

  void startListening() {
    LocationService.instance.startTracking(onPosition: _handlePosition);
  }

  void stopListening() {
    LocationService.instance.stopTracking();
  }

bool _inForeground = true;

/// Wird vom HomeScreen beim App-Lifecycle-Wechsel aufgerufen.
void setForeground(bool value) {
  _inForeground = value;
}

Future<void> _handlePosition(Position position) async {
  final lat = position.latitude;
  final lng = position.longitude;

  if (_inForeground) {
    await recordVisit(lat, lng);
  } else {
    // Im Hintergrund nur günstig protokollieren - Geohash-Berechnung,
    // Achievement-Checks und DB-Aggregation erst beim Zurückkehren, um
    // während des Hintergrundbetriebs möglichst wenig Akku zu verbrauchen.
    await StorageService.instance.logRawPoint(lat, lng, DateTime.now());
  }
}

/// Arbeitet alle im Hintergrund gesammelten Punkte in Aufzeichnungs-
/// reihenfolge ab - "stellt die Route nach" und deckt entsprechend Zellen
/// auf. Nutzt dieselbe recordVisit()-Pipeline wie Live-Punkte, inklusive
/// Lückenfüllung (_fillGap) als zusätzliches Sicherheitsnetz.
Future<void> replayQueuedTrack() async {
  final queued = await StorageService.instance.getQueuedTrackPoints();
  if (queued.isEmpty) return;

  for (final point in queued) {
    await recordVisit(point.lat, point.lng);
  }
  await StorageService.instance.clearTrackPoints(queued.map((p) => p.id).toList());
}

  /// Zentrale Methode, vom UI-Isolate und vom Android-Hintergrund-Isolate
  /// aufgerufen. Außerhalb des Spielgebiets passiert bewusst nichts.
  Future<void> recordVisit(double lat, double lng) async {
    if (!isInsideRegion(lat, lng)) return;

    final last = await StorageService.instance.getLastPosition();

    await _processPoint(lat, lng);
    if (last != null) {
      await _fillGap(last.$1, last.$2, lat, lng);
      await _trackDistance(last.$1, last.$2, lat, lng);
    }

    await StorageService.instance.recordExplorationDay(DateTime.now());
    await StorageService.instance.saveLastPosition(lat, lng);

    final stats = await getStats();
    await achievements.checkAll(stats);
    await placeAchievements.checkPlaceAt(lat, lng);
  }

  /// Deckt Zellen um den Punkt auf und trägt den Ort als besucht ein.
  Future<void> _processPoint(double lat, double lng) async {
    await _revealCells(lat, lng);
    final place = BoundaryService.instance.placeContaining(lat, lng);
    if (place != null) await placeAchievements.registerVisit(place);
  }

  /// Füllt die Lücke zwischen zwei Positionen (z.B. nach einer Pause im
  /// Hintergrund) entlang der Luftlinie. Näherung, nicht der echte Weg.
  Future<void> _fillGap(double lat1, double lng1, double lat2, double lng2) async {
    final gap = Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
    if (gap < _interpolationStepMeters * 1.5 || gap > _maxGapMeters) return;

    final steps = (gap / _interpolationStepMeters).floor();
    for (var i = 1; i < steps; i++) {
      final t = i / steps;
      final lat = lat1 + (lat2 - lat1) * t;
      final lng = lng1 + (lng2 - lng1) * t;
      if (!isInsideRegion(lat, lng)) continue;
      await _processPoint(lat, lng);
    }
  }

  Future<void> _revealCells(double lat, double lng) async {
    final geoHasher = GeoHasher();
    final centerHash = geoHasher.encode(lng, lat, precision: _geohashPrecision);
    final neighbors = geoHasher.neighbors(centerHash);

    for (final hash in [centerHash, ...neighbors.values]) {
      final decoded = geoHasher.decode(hash);
      final cellLat = decoded[1];
      final cellLng = decoded[0];

      // Einmalige Berechnung, danach in der DB gecached (siehe ExploredCell.placeId).
      final placeId = BoundaryService.instance.placeContaining(cellLat, cellLng)?.id;

      final cell = ExploredCell(
        geohash: hash,
        centerLat: cellLat,
        centerLng: cellLng,
        firstVisited: DateTime.now(),
        placeId: placeId,
      );
      final isNew = await StorageService.instance.addExploredCell(cell);
      if (isNew) {
        _totalExploredCount++;
        _newCellController.add(cell);
      }
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