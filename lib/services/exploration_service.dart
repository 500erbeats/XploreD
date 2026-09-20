import 'dart:async';
import 'package:dart_geohash/dart_geohash.dart';
import 'package:geolocator/geolocator.dart';

import '../models/achievement.dart';
import '../models/explored_cell.dart';
import 'achievement_service.dart';
import 'location_service.dart';
import 'storage_service.dart';

class ExplorationService {
  static const int _geohashPrecision = 7;

  final _newCellController = StreamController<ExploredCell>.broadcast();
  Stream<ExploredCell> get onNewCellExplored => _newCellController.stream;

  final achievements = AchievementService();
  Stream<AchievementDefinition> get onAchievementUnlocked => achievements.onUnlocked;

  int _totalExploredCount = 0;
  int get totalExploredCount => _totalExploredCount;

  Future<void> init() async {
    _totalExploredCount = await StorageService.instance.getExploredCellCount();
  }

  void startListening() {
    LocationService.instance.startTracking(onPosition: _handlePosition);
  }

  void stopListening() {
    LocationService.instance.stopTracking();
  }

  Future<void> _handlePosition(Position position) async {
    await recordVisit(position.latitude, position.longitude);
  }

  /// Zentrale Methode - wird sowohl vom UI-Isolate als auch vom Android-
  /// Background-Isolate (background_task_handler.dart) aufgerufen. Macht
  /// drei Dinge: 1) Geohash-Zellen erkunden, 2) Distanz zur letzten Position
  /// akkumulieren, 3) heutigen Tag als Erkundungstag vermerken - und prüft
  /// anschließend, ob dadurch neue Achievements freigeschaltet wurden.
  Future<void> recordVisit(double lat, double lng) async {
    await _revealCells(lat, lng);
    await _trackDistance(lat, lng);
    await StorageService.instance.recordExplorationDay(DateTime.now());
    await StorageService.instance.saveLastPosition(lat, lng);

    final stats = await getStats();
    await achievements.checkAll(stats);
  }

  Future<void> _revealCells(double lat, double lng) async {
    final geoHasher = GeoHasher();
    final centerHash = geoHasher.encode(lng, lat, precision: _geohashPrecision);
    final neighbors = geoHasher.neighbors(centerHash);

    for (final hash in [centerHash, ...neighbors.values]) {
      final decoded = geoHasher.decode(hash);
      final cell = ExploredCell(
        geohash: hash,
        centerLat: decoded[1],
        centerLng: decoded[0],
        firstVisited: DateTime.now(),
      );
      final isNew = await StorageService.instance.addExploredCell(cell);
      if (isNew) {
        _totalExploredCount++;
        _newCellController.add(cell);
      }
    }
  }

  Future<void> _trackDistance(double lat, double lng) async {
    final last = await StorageService.instance.getLastPosition();
    if (last == null) return; // Erster Punkt überhaupt - keine Distanz zu messen.

    final meters = Geolocator.distanceBetween(last.$1, last.$2, lat, lng);
    // Sprünge durch GPS-Ungenauigkeit (z.B. >2km "Teleport") nicht mitzählen.
    if (meters > 0 && meters < 2000) {
      await StorageService.instance.addDistanceMeters(meters);
    }
  }

  double get estimatedExploredAreaKm2 {
    const cellAreaKm2 = 0.15 * 0.15;
    return _totalExploredCount * cellAreaKm2;
  }

  /// Baut den vollständigen Stats-Snapshot aus persistenten Daten zusammen -
  /// wird sowohl intern für Achievement-Checks als auch vom Stats-Screen genutzt.
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

  /// Aktueller Streak = Anzahl aufeinanderfolgender Tage bis heute/gestern.
  /// Längster Streak = längste je erreichte Serie, auch wenn unterbrochen.
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
    final lastDay = sortedDays.last;
    final gapToToday = todayKey.difference(lastDay).inDays;

    // Streak gilt nur als "aktuell", wenn heute oder gestern noch erkundet wurde.
    final current = gapToToday <= 1 ? running : 0;

    return (current, longest);
  }

  void dispose() {
    _newCellController.close();
    achievements.dispose();
  }
}
