import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

import '../models/place.dart';
import '../models/region_config.dart';

final RegionConfig breisgauHochschwarzwaldRegion = RegionConfig(
  id: 'breisgau_hochschwarzwald',
  displayName: 'Breisgau-Hochschwarzwald',
  center: const LatLng(47.90, 7.85),
  // Deckt den gesamten Landkreis ab, von Breisach/Neuenburg im Westen bis
  // Löffingen/Schluchsee im Osten, Badenweiler im Süden bis Freiburg/
  // Gundelfingen im Norden.
  bounds: LatLngBounds(const LatLng(47.70, 7.50), const LatLng(48.10, 8.40)),
  boundariesAssetPath: 'assets/breisgau_hochschwarzwald_boundaries.geojson',
  places: [
    // Markgräflerland-Teil
    const PlaceDefinition(id: 'muellheim', name: 'Müllheim', lat: 47.8000, lng: 7.6330, radiusMeters: 1200),
    const PlaceDefinition(id: 'bad_krozingen', name: 'Bad Krozingen', lat: 47.9170, lng: 7.7000, radiusMeters: 1100),
    const PlaceDefinition(id: 'staufen', name: 'Staufen im Breisgau', lat: 47.8814, lng: 7.7314, radiusMeters: 800),
    const PlaceDefinition(id: 'ehrenkirchen', name: 'Ehrenkirchen', lat: 47.9153, lng: 7.7519, radiusMeters: 700),
    const PlaceDefinition(id: 'neuenburg', name: 'Neuenburg am Rhein', lat: 47.8147, lng: 7.5619, radiusMeters: 900),
    const PlaceDefinition(id: 'badenweiler', name: 'Badenweiler', lat: 47.8017, lng: 7.6719, radiusMeters: 700),
    const PlaceDefinition(id: 'heitersheim', name: 'Heitersheim', lat: 47.8753, lng: 7.6547, radiusMeters: 650),
    const PlaceDefinition(id: 'sulzburg', name: 'Sulzburg', lat: 47.8403, lng: 7.7092, radiusMeters: 500),
    const PlaceDefinition(id: 'auggen', name: 'Auggen', lat: 47.7869, lng: 7.5961, radiusMeters: 450),
    const PlaceDefinition(id: 'buggingen', name: 'Buggingen', lat: 47.8481, lng: 7.6369, radiusMeters: 500),
    const PlaceDefinition(id: 'ballrechten_dottingen', name: 'Ballrechten-Dottingen', lat: 47.8589, lng: 7.6975, radiusMeters: 450),
    const PlaceDefinition(id: 'bollschweil', name: 'Bollschweil', lat: 47.9206, lng: 7.7892, radiusMeters: 450),
    const PlaceDefinition(id: 'hartheim', name: 'Hartheim am Rhein', lat: 47.9367, lng: 7.6278, radiusMeters: 450),
    const PlaceDefinition(id: 'eschbach', name: 'Eschbach', lat: 47.8900, lng: 7.6550, radiusMeters: 450),

    // Kaiserstuhl/Tuniberg
    const PlaceDefinition(id: 'boetzingen', name: 'Bötzingen', lat: 48.0769, lng: 7.7256, radiusMeters: 500),
    const PlaceDefinition(id: 'breisach', name: 'Breisach am Rhein', lat: 48.0323, lng: 7.5805, radiusMeters: 800),
    const PlaceDefinition(id: 'eichstetten', name: 'Eichstetten am Kaiserstuhl', lat: 48.0942, lng: 7.7444, radiusMeters: 450),
    const PlaceDefinition(id: 'gottenheim', name: 'Gottenheim', lat: 48.0497, lng: 7.7289, radiusMeters: 450),
    const PlaceDefinition(id: 'ihringen', name: 'Ihringen', lat: 48.0500, lng: 7.6500, radiusMeters: 600),
    const PlaceDefinition(id: 'merdingen', name: 'Merdingen', lat: 48.0178, lng: 7.6883, radiusMeters: 400),
    const PlaceDefinition(id: 'march', name: 'March', lat: 48.0561, lng: 7.7819, radiusMeters: 500),
    const PlaceDefinition(id: 'umkirch', name: 'Umkirch', lat: 48.0328, lng: 7.7636, radiusMeters: 450),
    const PlaceDefinition(id: 'vogtsburg', name: 'Vogtsburg im Kaiserstuhl', lat: 48.0892, lng: 7.6317, radiusMeters: 600),

    // Hexental
    const PlaceDefinition(id: 'au', name: 'Au', lat: 47.9500, lng: 7.8333, radiusMeters: 350),
    const PlaceDefinition(id: 'ebringen', name: 'Ebringen', lat: 47.9500, lng: 7.7830, radiusMeters: 400),
    const PlaceDefinition(id: 'horben', name: 'Horben', lat: 47.9350, lng: 7.8589, radiusMeters: 400),
    const PlaceDefinition(id: 'merzhausen', name: 'Merzhausen', lat: 47.9664, lng: 7.8286, radiusMeters: 400),
    const PlaceDefinition(id: 'pfaffenweiler', name: 'Pfaffenweiler', lat: 47.9383, lng: 7.7572, radiusMeters: 400),
    const PlaceDefinition(id: 'schallstadt', name: 'Schallstadt', lat: 47.9581, lng: 7.7503, radiusMeters: 500),
    const PlaceDefinition(id: 'soelden', name: 'Sölden', lat: 47.9322, lng: 7.8117, radiusMeters: 350),
    const PlaceDefinition(id: 'wittnau', name: 'Wittnau', lat: 47.9458, lng: 7.8147, radiusMeters: 350),

    // Sonstige
    const PlaceDefinition(id: 'muenstertal', name: 'Münstertal/Schwarzwald', lat: 47.8547, lng: 7.7842, radiusMeters: 500),

    // Dreisamtal
    const PlaceDefinition(id: 'gundelfingen', name: 'Gundelfingen', lat: 48.0422, lng: 7.8669, radiusMeters: 550),
    const PlaceDefinition(id: 'heuweiler', name: 'Heuweiler', lat: 48.0517, lng: 7.9031, radiusMeters: 350),
    const PlaceDefinition(id: 'glottertal', name: 'Glottertal', lat: 48.0486, lng: 7.9550, radiusMeters: 450),
    const PlaceDefinition(id: 'kirchzarten', name: 'Kirchzarten', lat: 47.9670, lng: 7.9500, radiusMeters: 550),
    const PlaceDefinition(id: 'stegen', name: 'Stegen', lat: 47.9828, lng: 7.9639, radiusMeters: 400),
    const PlaceDefinition(id: 'buchenbach', name: 'Buchenbach', lat: 47.9608, lng: 8.0094, radiusMeters: 400),
    const PlaceDefinition(id: 'oberried', name: 'Oberried', lat: 47.9322, lng: 7.9487, radiusMeters: 400),
    const PlaceDefinition(id: 'sankt_maergen', name: 'Sankt Märgen', lat: 48.0083, lng: 8.0936, radiusMeters: 400),
    const PlaceDefinition(id: 'sankt_peter', name: 'Sankt Peter', lat: 47.9848, lng: 7.8440, radiusMeters: 400),

    // Hochschwarzwald
    const PlaceDefinition(id: 'breitnau', name: 'Breitnau', lat: 47.9392, lng: 8.0792, radiusMeters: 400),
    const PlaceDefinition(id: 'hinterzarten', name: 'Hinterzarten', lat: 47.9000, lng: 8.1000, radiusMeters: 500),
    const PlaceDefinition(id: 'feldberg', name: 'Feldberg (Schwarzwald)', lat: 47.8561, lng: 8.1117, radiusMeters: 500),
    const PlaceDefinition(id: 'titisee_neustadt', name: 'Titisee-Neustadt', lat: 47.9025, lng: 8.1481, radiusMeters: 900),
    const PlaceDefinition(id: 'eisenbach', name: 'Eisenbach (Hochschwarzwald)', lat: 47.9639, lng: 8.2719, radiusMeters: 400),
    const PlaceDefinition(id: 'friedenweiler', name: 'Friedenweiler', lat: 47.9175, lng: 8.2556, radiusMeters: 400),
    const PlaceDefinition(id: 'lenzkirch', name: 'Lenzkirch', lat: 47.8681, lng: 8.2050, radiusMeters: 500),
    const PlaceDefinition(id: 'loeffingen', name: 'Löffingen', lat: 47.8839, lng: 8.3436, radiusMeters: 600),
    const PlaceDefinition(id: 'schluchsee', name: 'Schluchsee', lat: 47.8194, lng: 8.1808, radiusMeters: 500),

    // Freiburg - offiziell kein Kreis-Mitglied, aber bewusst mit drin
    const PlaceDefinition(id: 'freiburg', name: 'Freiburg im Breisgau', lat: 47.9830, lng: 7.8500, radiusMeters: 3500),
  ],
);