import 'dart:async';

import '../models/achievement.dart';
import '../models/place.dart';
import 'boundary_service.dart';
import 'storage_service.dart';
import 'region_service.dart';

/// Orts-Achievements: "Besucht" (einmal im Ort gewesen) und "Erkundet"
/// (Zellenabdeckung im Ort >= Schwelle).
class PlaceAchievementService {
  static const double _completionThreshold = 0.85;
  static const double _cellAreaM2 = 150 * 150;

  final _unlockedController = StreamController<AchievementDefinition>.broadcast();
  Stream<AchievementDefinition> get onUnlocked => _unlockedController.stream;

  Set<String> _visitedCache = {};

  /// Lädt besuchte Orte in den Speicher und pflegt fehlende "Besucht"-
  /// Achievements still nach (z.B. nach der DB-Migration, ohne Toast-Flut).
  Future<void> init() async {
    _visitedCache = await StorageService.instance.getVisitedPlaceIds();
    final unlocked = await StorageService.instance.getUnlockedAchievementIds();
    for (final id in _visitedCache) {
      if (!unlocked.contains('visit_$id')) {
        await StorageService.instance.unlockAchievement('visit_$id');
      }
    }
    if (_visitedCache.length >= RegionService.instance.config.places.length) {
      await StorageService.instance.unlockAchievement('visit_all');
    }
  }

  Future<Set<String>> getVisitedIds() => StorageService.instance.getVisitedPlaceIds();

  /// Wird für jeden Punkt aufgerufen, der in einem Ort liegt (echt oder interpoliert).
  Future<void> registerVisit(PlaceDefinition place) async {
    if (_visitedCache.contains(place.id)) return; // billiger Check im Speicher

    final isNew = await StorageService.instance.markPlaceVisited(place.id);
    // Cache neu laden: der Hintergrund-Isolate schreibt in dieselbe Tabelle.
    _visitedCache = await StorageService.instance.getVisitedPlaceIds();
    if (!isNew) return;

    final id = 'visit_${place.id}';
    if (await StorageService.instance.unlockAchievement(id)) {
      _unlockedController.add(AchievementDefinition(
        id: id,
        title: 'Besucht: ${place.name}',
        description: '${place.name} zum ersten Mal besucht.',
        isUnlocked: (_) => true,
      ));
    }

    final total = RegionService.instance.config.places.length;
    if (_visitedCache.length >= total &&
        await StorageService.instance.unlockAchievement('visit_all')) {
      _unlockedController.add(AchievementDefinition(
        id: 'visit_all',
        title: 'Alle $total Orte besucht!',
        description: 'Du warst in jedem Ort von ${RegionService.instance.config.displayName}.',
        isUnlocked: (_) => true,
      ));
    }
  }

  Future<void> checkPlaceAt(double lat, double lng) async {
    final place = BoundaryService.instance.placeContaining(lat, lng);
    if (place == null) return;

    final unlocked = await StorageService.instance.getUnlockedAchievementIds();
    final achievementId = 'place_${place.id}';
    if (unlocked.contains(achievementId)) return;

    final ratio = await explorationRatio(place);
    if (ratio < _completionThreshold) return;

    final isNew = await StorageService.instance.unlockAchievement(achievementId);
    if (!isNew) return;

    _unlockedController.add(AchievementDefinition(
      id: achievementId,
      title: 'Ort erkundet: ${place.name}',
      description: '${place.name} (fast) vollständig aufgedeckt.',
      isUnlocked: (_) => true,
    ));

    await _checkRegionComplete({...unlocked, achievementId});
  }

  Future<void> _checkRegionComplete(Set<String> unlockedSoFar) async {
    final allPlaceIds = RegionService.instance.config.places.map((p) => 'place_${p.id}').toSet();
    if (allPlaceIds.difference(unlockedSoFar).isNotEmpty) return;

    final isNew = await StorageService.instance.unlockAchievement('region_complete');
    if (isNew) {
      _unlockedController.add(AchievementDefinition(
        id: 'region_complete',
        title: '${RegionService.instance.config.displayName} komplett!',
        description: 'Alle Orte der Region vollständig erkundet.',
        isUnlocked: (_) => true,
      ));
    }
  }

  Future<double> explorationRatio(PlaceDefinition place) async {
    final withinBoundary =
        await StorageService.instance.getExploredCellCountForPlace(place.id);
    final areaKm2 = BoundaryService.instance.areaKm2(place.id);
    final expectedCells = (areaKm2 * 1000000) / _cellAreaM2;
    if (expectedCells <= 0) return 0;
    return (withinBoundary / expectedCells).clamp(0.0, 1.0);
  }

  Future<List<(PlaceDefinition, double)>> getAllProgress() async {
    final results = <(PlaceDefinition, double)>[];
    for (final place in RegionService.instance.config.places) {
      results.add((place, await explorationRatio(place)));
    }
    return results;
  }

  void dispose() => _unlockedController.close();
}