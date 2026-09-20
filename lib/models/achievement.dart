/// Statischer Snapshot aller für Achievement-Checks relevanten Werte.
/// Wird nach jeder relevanten Änderung (neue Zelle, neue Distanz, neuer Tag)
/// neu zusammengestellt und gegen alle [AchievementDefinition]s geprüft.
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

/// Zentrale Liste aller Achievements. Neue Achievements werden einfach hier
/// ergänzt - der Rest (Freischalt-Logik, UI) reagiert automatisch darauf.
final List<AchievementDefinition> allAchievements = [
  AchievementDefinition(
    id: 'first_steps',
    title: 'Erste Schritte',
    description: 'Erkunde deine erste Zelle auf der Karte.',
    isUnlocked: (s) => s.exploredCells >= 1,
  ),
  AchievementDefinition(
    id: 'neighborhood',
    title: 'Nachbarschaft entdeckt',
    description: 'Erkunde 50 Zellen.',
    isUnlocked: (s) => s.exploredCells >= 50,
  ),
  AchievementDefinition(
    id: 'area_1km2',
    title: 'Erster Quadratkilometer',
    description: 'Decke 1 km² der Karte auf.',
    isUnlocked: (s) => s.areaKm2 >= 1,
  ),
  AchievementDefinition(
    id: 'area_10km2',
    title: 'Kleine Stadt',
    description: 'Decke 10 km² der Karte auf.',
    isUnlocked: (s) => s.areaKm2 >= 10,
  ),
  AchievementDefinition(
    id: 'distance_10km',
    title: 'Auf Achse',
    description: 'Lege insgesamt 10 km zurück.',
    isUnlocked: (s) => s.distanceKm >= 10,
  ),
  AchievementDefinition(
    id: 'distance_100km',
    title: 'Vielfahrer',
    description: 'Lege insgesamt 100 km zurück.',
    isUnlocked: (s) => s.distanceKm >= 100,
  ),
  AchievementDefinition(
    id: 'streak_3',
    title: 'Dranbleiber',
    description: 'Erkunde an 3 Tagen in Folge.',
    isUnlocked: (s) => s.currentStreak >= 3,
  ),
  AchievementDefinition(
    id: 'streak_7',
    title: 'Wochen-Entdecker',
    description: 'Erkunde 7 Tage in Folge.',
    isUnlocked: (s) => s.currentStreak >= 7,
  ),
];
