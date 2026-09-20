import 'package:flutter/material.dart';
import '../models/achievement.dart';
import '../services/exploration_service.dart';

class StatsScreen extends StatefulWidget {
  final ExplorationService exploration;
  const StatsScreen({super.key, required this.exploration});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  late Future<StatsSnapshot> _statsFuture;
  late Future<List<(AchievementDefinition, bool)>> _achievementsFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture = widget.exploration.getStats();
    _achievementsFuture = widget.exploration.achievements.getAllWithStatus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Statistik & Achievements')),
      body: FutureBuilder<StatsSnapshot>(
        future: _statsFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final stats = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatsGrid(stats: stats),
              const SizedBox(height: 24),
              Text('Achievements', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              FutureBuilder<List<(AchievementDefinition, bool)>>(
                future: _achievementsFuture,
                builder: (context, achSnapshot) {
                  if (!achSnapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return Column(
                    children: achSnapshot.data!
                        .map((entry) => _AchievementTile(definition: entry.$1, unlocked: entry.$2))
                        .toList(),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final StatsSnapshot stats;
  const _StatsGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Erkundete Fläche', '${stats.areaKm2.toStringAsFixed(2)} km²'),
      ('Erkundete Zellen', '${stats.exploredCells}'),
      ('Zurückgelegte Strecke', '${stats.distanceKm.toStringAsFixed(1)} km'),
      ('Erkundungstage', '${stats.explorationDays}'),
      ('Aktueller Streak', '${stats.currentStreak} Tage'),
      ('Längster Streak', '${stats.longestStreak} Tage'),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: items.map((item) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(item.$2,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(item.$1, style: TextStyle(color: Colors.grey[400], fontSize: 13)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _AchievementTile extends StatelessWidget {
  final AchievementDefinition definition;
  final bool unlocked;
  const _AchievementTile({required this.definition, required this.unlocked});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: unlocked ? 1.0 : 0.4,
      child: ListTile(
        leading: Icon(
          unlocked ? Icons.emoji_events : Icons.lock_outline,
          color: unlocked ? Colors.amber : Colors.grey,
        ),
        title: Text(definition.title),
        subtitle: Text(definition.description),
      ),
    );
  }
}
