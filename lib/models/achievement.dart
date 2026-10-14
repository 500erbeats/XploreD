/// Statischer Snapshot aller für Achievement-Checks relevanten Werte.
/// Wird nach jeder relevanten Änderung (neue Zelle, neue Distanz, neuer Tag)
/// neu zusammengestellt und gegen alle Achievement-Definitionen geprüft.
class StatsSnapshot {
  final int exploredCells;
  final double areaKm2;
  final double distanceKm;
  final int explorationDays;
  final int currentStreak;
  final int longestStreak;

  const StatsSnapshot({
    required this.exploredCells,
    required this.areaKm2,
    required this.distanceKm,
    required this.explorationDays,
    required this.currentStreak,
    required this.longestStreak,
  });
}

class AchievementDefinition {
  final String id;
  final String title;
  final String description;
  final bool Function(StatsSnapshot stats) isUnlocked;

  const AchievementDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.isUnlocked,
  });
}

/// Einstufige Achievements. Die Fortschritts-Achievements (Strecke, Zellen,
/// Tage, Streak) laufen über [tieredAchievements] in Bronze/Silber/Gold.
final List<AchievementDefinition> allAchievements = [
  AchievementDefinition(
    id: 'first_steps',
    title: 'Erste Schritte',
    description: 'Erkunde deine erste Zelle auf der Karte.',
    isUnlocked: (s) => s.exploredCells >= 1,
  ),
];

enum AchievementTier { bronze, silver, gold }

String tierLabel(AchievementTier tier) => switch (tier) {
      AchievementTier.bronze => 'Bronze',
      AchievementTier.silver => 'Silber',
      AchievementTier.gold => 'Gold',
    };

/// Tausendertrennzeichen im deutschen Stil: 1000 -> "1.000".
String formatNumber(num n) {
  final s = n.round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// Ein Achievement mit drei Stufen. In der DB wird jede Stufe als eigene ID
/// gespeichert: "<id>_bronze", "<id>_silver", "<id>_gold".
class TieredAchievementDefinition {
  final String id;
  final String title;
  final String unit;

  /// Schwellenwerte für Bronze, Silber, Gold (aufsteigend).
  final List<num> thresholds;
  final num Function(StatsSnapshot stats) valueOf;

  /// Nachkommastellen bei der Anzeige des aktuellen Werts.
  final int decimals;

  const TieredAchievementDefinition({
    required this.id,
    required this.title,
    required this.unit,
    required this.thresholds,
    required this.valueOf,
    this.decimals = 0,
  });

  String tierId(AchievementTier tier) => '${id}_${tier.name}';

  /// Anzahl erreichter Stufen (0 bis 3).
  int tiersReached(num value) => thresholds.where((t) => value >= t).length;
}

final List<TieredAchievementDefinition> tieredAchievements = [
  TieredAchievementDefinition(
    id: 'distance',
    title: 'Strecke',
    unit: 'km',
    thresholds: [100, 500, 1000],
    valueOf: (s) => s.distanceKm,
    decimals: 1,
  ),
  TieredAchievementDefinition(
    id: 'cells',
    title: 'Erkundete Zellen',
    unit: 'Zellen',
    thresholds: [100, 1000, 10000],
    valueOf: (s) => s.exploredCells,
  ),
  TieredAchievementDefinition(
    id: 'days',
    title: 'Erkundungstage',
    unit: 'Tage',
    thresholds: [7, 28, 180],
    valueOf: (s) => s.explorationDays,
  ),
  TieredAchievementDefinition(
    id: 'streak',
    title: 'Längster Streak',
    unit: 'Tage',
    thresholds: [7, 14, 31],
    valueOf: (s) => s.longestStreak,
  ),
];