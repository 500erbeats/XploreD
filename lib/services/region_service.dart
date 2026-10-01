import '../models/region_config.dart';

/// Hält die aktuell aktive Region. Muss GANZ am Anfang von main() über
/// configure() gesetzt werden, bevor irgendein anderer Service (Boundary,
/// Exploration, ...) darauf zugreift.
class RegionService {
  static final RegionService instance = RegionService._internal();
  RegionService._internal();

  RegionConfig? _config;

  void configure(RegionConfig config) {
    _config = config;
  }

  RegionConfig get config {
    final c = _config;
    if (c == null) {
      throw StateError(
        'RegionService.configure() wurde nicht vor dem ersten Zugriff aufgerufen.',
      );
    }
    return c;
  }
}