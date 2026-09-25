import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/place.dart';

/// Lädt die echten Gemeindegrenzen (OSM-Polygone) und bietet einen
/// Punkt-in-Polygon-Test an.
class BoundaryService {
  static final BoundaryService instance = BoundaryService._internal();
  BoundaryService._internal();

  final Map<String, List<List<LatLng>>> _boundaries = {};
  final Map<String, LatLngBounds> _bounds = {};

  bool _loaded = false;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;

    final raw = await rootBundle.loadString('assets/markgraeflerland_boundaries.geojson');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final features = decoded['features'] as List<dynamic>;

    for (final feature in features) {
  final props = feature['properties'] as Map<String, dynamic>?;
  final id = props?['id'] as String?;

  // Features ohne gültige ID überspringen (z.B. unbenannte Punkt-Marker),
  // statt die gesamte Ladung mit einer Exception abzubrechen.
  if (id == null) continue;

  final geometry = feature['geometry'] as Map<String, dynamic>?;
  if (geometry == null) continue;

  final type = geometry['type'] as String?;
  final coords = geometry['coordinates'] as List<dynamic>?;
  if (type == null || coords == null) continue;

  final rings = <List<LatLng>>[];

  if (type == 'Polygon') {
    for (final ring in coords) {
      rings.add(_parseRing(ring as List<dynamic>));
    }
  } else if (type == 'MultiPolygon') {
    for (final polygon in coords) {
      for (final ring in polygon as List<dynamic>) {
        rings.add(_parseRing(ring as List<dynamic>));
      }
    }
  } else {
    continue; // Point, LineString etc. sind für uns irrelevant.
  }

  if (rings.isEmpty) continue;

  _boundaries[id] = rings;
  _bounds[id] = _computeBounds(rings);
}

    _loaded = true;
  }

  List<LatLng> _parseRing(List<dynamic> ring) {
    return ring.map((point) {
      final coord = point as List<dynamic>;
      return LatLng((coord[1] as num).toDouble(), (coord[0] as num).toDouble());
    }).toList();
  }

  LatLngBounds _computeBounds(List<List<LatLng>> rings) {
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final ring in rings) {
      for (final p in ring) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
    }
    return LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
  }

  bool _pointInRing(LatLng point, List<LatLng> ring) {
    bool inside = false;
    final n = ring.length;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final pi = ring[i];
      final pj = ring[j];

      final intersects = ((pi.latitude > point.latitude) != (pj.latitude > point.latitude)) &&
          (point.longitude <
              (pj.longitude - pi.longitude) * (point.latitude - pi.latitude) /
                      (pj.latitude - pi.latitude) +
                  pi.longitude);

      if (intersects) inside = !inside;
    }
    return inside;
  }

  bool _pointInPlace(LatLng point, String placeId) {
    final LatLngBounds? bbox = _bounds[placeId];
    if (bbox == null) return false;
    if (!bbox.contains(point)) return false;

    final rings = _boundaries[placeId]!;
    var crossings = 0;
    for (final ring in rings) {
      if (_pointInRing(point, ring)) crossings++;
    }
    return crossings.isOdd;
  }

  PlaceDefinition? placeContaining(double lat, double lng) {
    final point = LatLng(lat, lng);

    if (!_loaded) {
      return nearestPlace(lat, lng, onlyIfInside: true);
    }

    for (final place in markgraeflerlandPlaces) {
      if (_pointInPlace(point, place.id)) return place;
    }
    return null;
  }

  double areaKm2(String placeId) {
    final rings = _boundaries[placeId];
    if (rings == null || rings.isEmpty) return 0;

    double total = 0;
    for (final ring in rings) {
      total += _ringAreaKm2(ring).abs();
    }
    return total;
  }

  double _ringAreaKm2(List<LatLng> ring) {
    if (ring.length < 3) return 0;

    final refLat = ring.first.latitude;
    const metersPerDegLat = 111320.0;
    final metersPerDegLng = 111320.0 * math.cos(refLat * math.pi / 180);

    double area = 0;
    for (int i = 0; i < ring.length - 1; i++) {
      final p1 = ring[i];
      final p2 = ring[i + 1];
      final x1 = p1.longitude * metersPerDegLng;
      final y1 = p1.latitude * metersPerDegLat;
      final x2 = p2.longitude * metersPerDegLng;
      final y2 = p2.latitude * metersPerDegLat;
      area += (x1 * y2 - x2 * y1);
    }
    return (area / 2).abs() / 1e6;
  }
}