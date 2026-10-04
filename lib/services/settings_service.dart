import 'storage_service.dart';

/// Typisierter Zugriff auf alle Nutzer-Einstellungen. Kapselt Defaults und
/// Parsing, damit der Rest der App nie mit rohen String-Keys hantiert.
class SettingsService {
  static const _keyBackgroundTracking = 'background_tracking_enabled';
  static const _keyDistanceFilter = 'distance_filter_m';
  static const _keyOnboardingCompleted = 'onboarding_completed';
  static const _keyMapTheme = 'map_theme'; 
  static const defaultDistanceFilter = 50.0;
  static const _keyPlaceIdBackfillDone = 'place_id_backfill_done';
  static const _keyCartoApiKey = 'carto_api_key';

  Future<bool> isPlaceIdBackfillDone() async {
    final value = await StorageService.instance.getSetting(_keyPlaceIdBackfillDone);
    return value == 'true';
  }

  Future<void> setPlaceIdBackfillDone(bool done) {
    return StorageService.instance.setSetting(_keyPlaceIdBackfillDone, '$done');
  }
  Future<bool> isBackgroundTrackingEnabled() async {
    final value = await StorageService.instance.getSetting(_keyBackgroundTracking);
    return value != 'false'; // Standardmäßig aktiviert.
  }

  Future<void> setBackgroundTrackingEnabled(bool enabled) {
    return StorageService.instance.setSetting(_keyBackgroundTracking, '$enabled');
  }

  Future<double> getDistanceFilterMeters() async {
    final value = await StorageService.instance.getSetting(_keyDistanceFilter);
    return value != null ? double.parse(value) : defaultDistanceFilter;
  }

  Future<void> setDistanceFilterMeters(double meters) {
    return StorageService.instance.setSetting(_keyDistanceFilter, '$meters');
  }

  Future<bool> isOnboardingCompleted() async {
    final value = await StorageService.instance.getSetting(_keyOnboardingCompleted);
    return value == 'true';
  }

  Future<void> setOnboardingCompleted(bool completed) {
    return StorageService.instance.setSetting(_keyOnboardingCompleted, '$completed');
  }

  /// 'light' = helle Karte + dunkler Nebel (klassischer Fog-of-War-Look).
/// 'dark'  = dunkle Karte + heller Nebel (invertiert).
Future<String> getMapTheme() async {
  final value = await StorageService.instance.getSetting(_keyMapTheme);
  return value ?? 'light'; // Neuer Standard - siehe Begründung im Chat.
}

Future<void> setMapTheme(String theme) {
  return StorageService.instance.setSetting(_keyMapTheme, theme);
}

Future<String?> getCartoApiKey() async {
  return StorageService.instance.getSetting(_keyCartoApiKey);
}

Future<void> setCartoApiKey(String key) {
  return StorageService.instance.setSetting(_keyCartoApiKey, key);
}

}
