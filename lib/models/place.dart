import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../services/region_service.dart';

class PlaceDefinition {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final double radiusMeters;

  const PlaceDefinition({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.radiusMeters,
  });
}

PlaceDefinition? nearestPlace(double lat, double lng, {bool onlyIfInside = false}) {
  final places = RegionService.instance.config.places;
  PlaceDefinition? closest;
  double closestDist = double.infinity;

  for (final place in places) {
    final d = Geolocator.distanceBetween(place.lat, place.lng, lat, lng);
    if (d < closestDist) {
      closestDist = d;
      closest = place;
    }
  }

  if (onlyIfInside && closest != null && closestDist > closest.radiusMeters) {
    return null;
  }
  return closest;
}

bool isInsideRegion(double lat, double lng) =>
    RegionService.instance.config.bounds.contains(LatLng(lat, lng));