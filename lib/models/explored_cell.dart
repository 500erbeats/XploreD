/// Repräsentiert eine einzelne erkundete Grid-Zelle (Geohash-basiert).
///
/// Wir speichern nicht jeden GPS-Punkt, sondern runden auf ein Geohash-Grid
/// mit Präzision 7 (~150m x 150m Zellengröße). Das macht Deduplizierung
/// trivial: derselbe Ort erzeugt immer denselben Geohash-String, egal wie
/// oft er besucht wird -> INSERT OR IGNORE reicht aus.
/// Repräsentiert eine einzelne erkundete Grid-Zelle (Geohash-basiert).
class ExploredCell {
  final String geohash;
  final double centerLat;
  final double centerLng;
  final DateTime firstVisited;
  /// Die Orts-ID (z.B. 'muellheim'), falls die Zelle innerhalb einer echten
  /// Gemeindegrenze liegt - sonst null ("Land"). Wird EINMALIG beim
  /// Erkunden berechnet und cached, damit Painter und Achievement-Check nie
  /// erneut einen teuren Punkt-in-Polygon-Test für dieselbe Zelle brauchen.
  final String? placeId;

  const ExploredCell({
    required this.geohash,
    required this.centerLat,
    required this.centerLng,
    required this.firstVisited,
    this.placeId,
  });

  Map<String, dynamic> toMap() => {
        'geohash': geohash,
        'center_lat': centerLat,
        'center_lng': centerLng,
        'first_visited': firstVisited.millisecondsSinceEpoch,
        'place_id': placeId,
      };

  factory ExploredCell.fromMap(Map<String, dynamic> map) => ExploredCell(
        geohash: map['geohash'] as String,
        centerLat: map['center_lat'] as double,
        centerLng: map['center_lng'] as double,
        firstVisited: DateTime.fromMillisecondsSinceEpoch(map['first_visited'] as int),
        placeId: map['place_id'] as String?,
      );
}
