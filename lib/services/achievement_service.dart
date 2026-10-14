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

    for (final tiered in tieredAchievements) {
      final reached = tiered.tiersReached(tiered.valueOf(stats));

      // Alle erreichten Stufen werden freigeschaltet, gemeldet (Toast) wird
      // aber nur die höchste NEU erreichte - sonst gäbe es beim ersten Check
      // nach dem Update eine Toast-Flut für schon längst erreichte Stufen.
      AchievementTier? highestNew;
      for (var i = 0; i < reached; i++) {
        final tier = AchievementTier.values[i];
        final id = tiered.tierId(tier);
        if (alreadyUnlocked.contains(id)) continue;
        final isNew = await StorageService.instance.unlockAchievement(id);
        if (isNew) highestNew = tier;
      }

      if (highestNew != null) {
        _unlockedController.add(AchievementDefinition(
          id: tiered.tierId(highestNew),
          title: '${tiered.title}: ${tierLabel(highestNew)}',
          description:
              '${formatNumber(tiered.thresholds[highestNew.index])} ${tiered.unit} erreicht.',
          isUnlocked: (_) => true,
        ));
      }
    }
  }

  /// Für die Stats-Screen-Anzeige: einstufige Achievements mit Status.
  Future<List<(AchievementDefinition, bool)>> getAllWithStatus() async {
    final unlocked = await StorageService.instance.getUnlockedAchievementIds();
    return allAchievements.map((def) => (def, unlocked.contains(def.id))).toList();
  }

  void dispose() => _unlockedController.close();
}