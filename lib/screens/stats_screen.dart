import 'package:flutter/material.dart';
import '../models/achievement.dart';
import '../services/exploration_service.dart';
import '../models/place.dart';
import '../services/storage_service.dart';

class StatsScreen extends StatefulWidget {
  final ExplorationService exploration;
  const StatsScreen({super.key, required this.exploration});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  late Future<StatsSnapshot> _statsFuture;
  late Future<List<(AchievementDefinition, bool)>> _achievementsFuture;
  late Future<_PlaceProgressData> _placesFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture = widget.exploration.getStats();
    _achievementsFuture = widget.exploration.achievements.getAllWithStatus();
    _placesFuture = _loadPlaces();
  } // <- initState endet HIER

  // Eigene Methode der Klasse, nicht in initState verschachtelt:
  Future<_PlaceProgressData> _loadPlaces() async {
    final visited = await StorageService.instance.getVisitedPlaceIds();
    final progress = await widget.exploration.placeAchievements.getAllProgress();
    return _PlaceProgressData(visited, progress);
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
              FutureBuilder<_PlaceProgressData>(
                future: _placesFuture,
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return _PlacesSection(data: snap.data!);
                },
              ),
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
class _PlaceProgressData {
  final Set<String> visited;
  final List<(PlaceDefinition, double)> progress;
  const _PlaceProgressData(this.visited, this.progress);
}

class _PlacesSection extends StatelessWidget {
  final _PlaceProgressData data;
  const _PlacesSection({required this.data});

  @override
  Widget build(BuildContext context) {
    final total = data.progress.length;
    final visited = data.visited.length;
    final sorted = [...data.progress]..sort((a, b) => a.$1.name.compareTo(b.$1.name));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Orte besucht', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('$visited/$total', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text(total == 0 ? '' : '${(visited / total * 100).round()} %'),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : visited / total,
            minHeight: 10,
          ),
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Alle Orte anzeigen'),
          children: sorted.map((entry) {
            final place = entry.$1;
            final ratio = entry.$2;
            final isVisited = data.visited.contains(place.id);
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                isVisited ? Icons.check_circle : Icons.radio_button_unchecked,
                color: isVisited ? Colors.greenAccent : Colors.grey,
              ),
              title: Text(place.name),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: ratio, minHeight: 6),
                ),
              ),
              trailing: Text('${(ratio * 100).round()} %'),
            );
          }).toList(),
        ),
      ],
    );
  }
}