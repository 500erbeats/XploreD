import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

import '../models/place.dart';
import '../models/region_config.dart';

/// Bewusst schlanker Start: Freiburg als EIN großer Ort (wie bisher Lörrach
/// im Markgräflerland), noch keine einzelnen Stadtteile als separate
/// Achievements. Lässt sich später erweitern, ohne die Architektur zu ändern.
final RegionConfig freiburgRegion = RegionConfig(
  id: 'freiburg',
  displayName: 'Freiburg',
  center: const LatLng(47.9830, 7.8500),
  bounds: LatLngBounds(const LatLng(47.93, 7.76), const LatLng(48.03, 7.93)),
  boundariesAssetPath: 'assets/freiburg_boundaries.geojson',
  places: [
    const PlaceDefinition(
      id: 'freiburg',
      name: 'Freiburg im Breisgau',
      lat: 47.9830,
      lng: 7.8500,
      radiusMeters: 3500,
    ),
  ],
);