/// Repräsentiert eine einzelne erkundete Grid-Zelle (Geohash-basiert).
///
/// Wir speichern nicht jeden GPS-Punkt, sondern runden auf ein Geohash-Grid
/// mit Präzision 7 (~150m x 150m Zellengröße). Das macht Deduplizierung
/// trivial: derselbe Ort erzeugt immer denselben Geohash-String, egal wie
/// oft er besucht wird -> INSERT OR IGNORE reicht aus.
class ExploredCell {
  final String geohash;
  final double centerLat;
  final double centerLng;
  final DateTime firstVisited;

  const ExploredCell({
    required this.geohash,
    required this.centerLat,
    required this.centerLng,
    required this.firstVisited,
  });

  Map<String, dynamic> toMap() => {
        'geohash': geohash,
        'center_lat': centerLat,
        'center_lng': centerLng,
        'first_visited': firstVisited.millisecondsSinceEpoch,
      };

  factory ExploredCell.fromMap(Map<String, dynamic> map) => ExploredCell(
        geohash: map['geohash'] as String,
        centerLat: map['center_lat'] as double,
        centerLng: map['center_lng'] as double,
        firstVisited:
            DateTime.fromMillisecondsSinceEpoch(map['first_visited'] as int),
      );
}
