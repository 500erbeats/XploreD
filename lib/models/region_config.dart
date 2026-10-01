import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'place.dart';

/// Fasst alles zusammen, was eine Region (Markgräflerland, Freiburg, ...)
/// ausmacht. Jeder Flavor konfiguriert beim Start GENAU eine Instanz davon.
class RegionConfig {
  final String id;
  final String displayName;
  final LatLng center;
  final LatLngBounds bounds;
  final String boundariesAssetPath;
  final List<PlaceDefinition> places;

  const RegionConfig({
    required this.id,
    required this.displayName,
    required this.center,
    required this.bounds,
    required this.boundariesAssetPath,
    required this.places,
  });
}