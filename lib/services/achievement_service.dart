import 'dart:async';
import '../models/achievement.dart';
import 'storage_service.dart';

/// Prüft nach jeder relevanten Statistik-Änderung, ob neue Achievements
/// freigeschaltet wurden, und meldet diese über einen Stream (für Toasts in
/// der UI).
class AchievementService {
  final _unlockedController = StreamController<AchievementDefinition>.broadcast();
  Stream<AchievementDefinition> get onUnlocked => _unlockedController.stream;

  Future<void> checkAll(StatsSnapshot stats) async {
    final alreadyUnlocked = await StorageService.instance.getUnlockedAchievementIds();

    for (final def in allAchievements) {
      if (alreadyUnlocked.contains(def.id)) continue;
      if (def.isUnlocked(stats)) {
        final isNew = await StorageService.instance.unlockAchievement(def.id);
        if (isNew) _unlockedController.add(def);
      }
    }
  }

  /// Für die Stats-Screen-Anzeige: alle Achievements mit ihrem Freischalt-Status.
  Future<List<(AchievementDefinition, bool)>> getAllWithStatus() async {
    final unlocked = await StorageService.instance.getUnlockedAchievementIds();
    return allAchievements.map((def) => (def, unlocked.contains(def.id))).toList();
  }

  void dispose() => _unlockedController.close();
}
