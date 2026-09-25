import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

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

final List<PlaceDefinition> markgraeflerlandPlaces = [
  const PlaceDefinition(id: 'muellheim', name: 'Müllheim', lat: 47.8000, lng: 7.6330, radiusMeters: 1200),
  const PlaceDefinition(id: 'bad_krozingen', name: 'Bad Krozingen', lat: 47.9170, lng: 7.7000, radiusMeters: 1100),
  const PlaceDefinition(id: 'lörrach', name: 'Lörrach', lat: 47.6170, lng: 7.6670, radiusMeters: 1600),
  const PlaceDefinition(id: 'weil_am_rhein', name: 'Weil am Rhein', lat: 47.5947, lng: 7.6108, radiusMeters: 1300),
  const PlaceDefinition(id: 'staufen', name: 'Staufen im Breisgau', lat: 47.8814, lng: 7.7314, radiusMeters: 800),
  const PlaceDefinition(id: 'ehrenkirchen', name: 'Ehrenkirchen', lat: 47.9153, lng: 7.7519, radiusMeters: 700),
  const PlaceDefinition(id: 'neuenburg', name: 'Neuenburg am Rhein', lat: 47.8147, lng: 7.5619, radiusMeters: 900),
  const PlaceDefinition(id: 'badenweiler', name: 'Badenweiler', lat: 47.8017, lng: 7.6719, radiusMeters: 700),
  const PlaceDefinition(id: 'heitersheim', name: 'Heitersheim', lat: 47.8753, lng: 7.6547, radiusMeters: 650),
  const PlaceDefinition(id: 'kandern', name: 'Kandern', lat: 47.7170, lng: 7.6670, radiusMeters: 700),
  const PlaceDefinition(id: 'steinen', name: 'Steinen', lat: 47.6453, lng: 7.7403, radiusMeters: 650),
  const PlaceDefinition(id: 'sulzburg', name: 'Sulzburg', lat: 47.8403, lng: 7.7092, radiusMeters: 500),
  const PlaceDefinition(id: 'auggen', name: 'Auggen', lat: 47.7869, lng: 7.5961, radiusMeters: 450),
  const PlaceDefinition(id: 'schliengen', name: 'Schliengen', lat: 47.7556, lng: 7.5772, radiusMeters: 550),
  const PlaceDefinition(id: 'bad_bellingen', name: 'Bad Bellingen', lat: 47.7307, lng: 7.5575, radiusMeters: 500),
  const PlaceDefinition(id: 'buggingen', name: 'Buggingen', lat: 47.8481, lng: 7.6369, radiusMeters: 500),
  const PlaceDefinition(id: 'ballrechten_dottingen', name: 'Ballrechten-Dottingen', lat: 47.8589, lng: 7.6975, radiusMeters: 450),
  const PlaceDefinition(id: 'efringen_kirchen', name: 'Efringen-Kirchen', lat: 47.6556, lng: 7.5652, radiusMeters: 550),
  const PlaceDefinition(id: 'bollschweil', name: 'Bollschweil', lat: 47.9206, lng: 7.7892, radiusMeters: 450),
  const PlaceDefinition(id: 'binzen', name: 'Binzen', lat: 47.6311, lng: 7.6233, radiusMeters: 450),
  const PlaceDefinition(id: 'eimeldingen', name: 'Eimeldingen', lat: 47.6306, lng: 7.5947, radiusMeters: 400),
  const PlaceDefinition(id: 'malsburg_marzell', name: 'Malsburg-Marzell', lat: 47.7708, lng: 7.7256, radiusMeters: 400),
  const PlaceDefinition(id: 'hartheim', name: 'Hartheim am Rhein', lat: 47.9367, lng: 7.6278, radiusMeters: 450),
  const PlaceDefinition(id: 'eschbach', name: 'Eschbach', lat: 47.8900, lng: 7.6550, radiusMeters: 450),
  const PlaceDefinition(id: 'fischingen', name: 'Fischingen', lat: 47.6500, lng: 7.6000, radiusMeters: 350),
  const PlaceDefinition(id: 'schallbach', name: 'Schallbach', lat: 47.6544, lng: 7.6267, radiusMeters: 350),
  const PlaceDefinition(id: 'ruemmingen', name: 'Rümmingen', lat: 47.6406, lng: 7.6433, radiusMeters: 350),
  const PlaceDefinition(id: 'wittlingen', name: 'Wittlingen', lat: 47.6553, lng: 7.6497, radiusMeters: 350),
];

final LatLngBounds markgraeflerlandBounds = LatLngBounds(
  const LatLng(47.56, 7.50),
  const LatLng(47.96, 7.85),
);

PlaceDefinition? nearestPlace(double lat, double lng, {bool onlyIfInside = false}) {
  PlaceDefinition? closest;
  double closestDist = double.infinity;

  for (final place in markgraeflerlandPlaces) {
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