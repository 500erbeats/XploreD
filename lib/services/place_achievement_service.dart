import 'dart:async';
import '../models/achievement.dart';
import '../models/place.dart';
import 'storage_service.dart';
import 'boundary_service.dart';

/// Prüft Orts-Achievements: ein Ort gilt als "erkundet", wenn die geschätzte
/// Zellenabdeckung innerhalb seines Radius einen Schwellenwert erreicht.
/// Läuft parallel zum globalen AchievementService, weil die Prüfung
/// ortsbezogene DB-Abfragen braucht, die nicht in den globalen StatsSnapshot
/// passen.
class PlaceAchievementService {
  static const double _completionThreshold = 0.85;
  static const double _cellAreaM2 = 150 * 150; // ~Geohash-Zellenfläche

  final _unlockedController = StreamController<AchievementDefinition>.broadcast();
  Stream<AchievementDefinition> get onUnlocked => _unlockedController.stream;

  /// Prüft NUR den Ort, in dem der übergebene Punkt liegt - nicht bei jedem
  /// GPS-Update alle 12 Orte durchrechnen, aus Performance-Gründen.
  Future<void> checkPlaceAt(double lat, double lng) async {
    final place = nearestPlace(lat, lng, onlyIfInside: true);
    if (place == null) return; // Punkt liegt auf dem Land, kein Ort betroffen.

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
    final allPlaceIds = markgraeflerlandPlaces.map((p) => 'place_${p.id}').toSet();
    if (allPlaceIds.difference(unlockedSoFar).isNotEmpty) return;
    final isNew = await StorageService.instance.unlockAchievement('region_complete');
    if (isNew) {
      _unlockedController.add(AchievementDefinition(
        id: 'region_complete',
        title: 'Markgräflerland komplett!',
        description: 'Alle Orte der Region vollständig erkundet.',
        isUnlocked: (_) => true,
      ));
    }
  }

  /// Grobe Schätzung: tatsächlich erkundete Zellen im Ortsradius geteilt
  /// durch die geschätzte Anzahl Zellen, die die Kreisfläche des Ortes
  /// komplett abdecken würde. 0.85 statt 1.0 als Schwelle, weil das
  /// Geohash-Raster einen Kreis nie perfekt lückenlos abdeckt.
 Future<double> explorationRatio(PlaceDefinition place) async {
  // Direkter, indexierter COUNT-Query statt Bounding-Box-Laden + Punkt-in-
  // Polygon-Filterung - die Zuordnung steckt ja schon gecached in der DB.
  final withinBoundary = await StorageService.instance.getExploredCellCountForPlace(place.id);

  final areaKm2 = BoundaryService.instance.areaKm2(place.id);
  final expectedCells = (areaKm2 * 1000000) / _cellAreaM2;
  if (expectedCells <= 0) return 0;
  return (withinBoundary / expectedCells).clamp(0.0, 1.0);
}

  /// Für den Stats-Screen: Fortschritt aller Orte auf einmal.
  Future<List<(PlaceDefinition, double)>> getAllProgress() async {
    final results = <(PlaceDefinition, double)>[];
    for (final place in markgraeflerlandPlaces) {
      results.add((place, await explorationRatio(place)));
    }
    return results;
  }

  void dispose() => _unlockedController.close();
}