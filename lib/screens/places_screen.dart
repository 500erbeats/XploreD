import 'package:flutter/material.dart';

import '../models/place.dart';
import '../services/boundary_service.dart';
import '../services/region_service.dart';
import '../services/storage_service.dart';

enum _Filter { all, visited, open }

enum _Sort { progress, name }

class _PlaceRow {
  final PlaceDefinition place;
  final int cells;
  final double? percent; // null = Fläche unbekannt
  final bool visited;
  const _PlaceRow(this.place, this.cells, this.percent, this.visited);
}

class PlacesScreen extends StatefulWidget {
  const PlacesScreen({super.key});

  @override
  State<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends State<PlacesScreen> {
  static const _cellAreaKm2 = 0.15 * 0.15;

  List<_PlaceRow> _rows = [];
  bool _loading = true;
  _Filter _filter = _Filter.all;
  _Sort _sort = _Sort.progress;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final counts = await StorageService.instance.getExploredCellCountsByPlace();
    final visitedIds = await StorageService.instance.getVisitedPlaceIds();

    final rows = RegionService.instance.config.places.map((p) {
      final cells = counts[p.id] ?? 0;
      final area = BoundaryService.instance.areaKm2(p.id);
      final percent = area > 0
          ? (cells * _cellAreaKm2 / area * 100).clamp(0.0, 100.0).toDouble()
          : null;
      return _PlaceRow(p, cells, percent, visitedIds.contains(p.id) || cells > 0);
    }).toList();

    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  List<_PlaceRow> get _visibleRows {
    final list = _rows.where((r) {
      switch (_filter) {
        case _Filter.all:
          return true;
        case _Filter.visited:
          return r.visited;
        case _Filter.open:
          return !r.visited;
      }
    }).toList();

    list.sort((a, b) {
      if (_sort == _Sort.progress) {
        final byPercent = (b.percent ?? -1).compareTo(a.percent ?? -1);
        if (byPercent != 0) return byPercent;
      }
      return a.place.name.compareTo(b.place.name);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visibleRows;
    final visitedCount = _rows.where((r) => r.visited).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Orte'),
        actions: [
          PopupMenuButton<_Sort>(
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (s) => setState(() => _sort = s),
            itemBuilder: (_) => const [
              PopupMenuItem(value: _Sort.progress, child: Text('Nach Fortschritt')),
              PopupMenuItem(value: _Sort.name, child: Text('Nach Name')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '$visitedCount / ${_rows.length} Orte besucht · '
                      'Tippen zeigt den Ort mit Grenze auf der Karte',
                      style: TextStyle(color: Colors.grey[400], fontSize: 13),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: SegmentedButton<_Filter>(
                    segments: const [
                      ButtonSegment(value: _Filter.all, label: Text('Alle')),
                      ButtonSegment(value: _Filter.visited, label: Text('Besucht')),
                      ButtonSegment(value: _Filter.open, label: Text('Offen')),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (s) => setState(() => _filter = s.first),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, i) => _buildTile(rows[i]),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTile(_PlaceRow row) {
    final percent = row.percent;
    final text = percent == null
        ? '${row.cells} Zellen'
        : '${percent.toStringAsFixed(percent < 10 ? 1 : 0)} % erkundet · ${row.cells} Zellen';

    return ListTile(
      leading: Icon(
        row.visited ? Icons.check_circle : Icons.radio_button_unchecked,
        color: row.visited ? Colors.greenAccent : Colors.grey,
      ),
      title: Text(row.place.name),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              value: (percent ?? 0) / 100,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(height: 4),
            Text(text, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
          ],
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.pop(context, row.place.id),
    );
  }
}