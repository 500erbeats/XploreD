import 'storage_service.dart';

/// Typisierter Zugriff auf alle Nutzer-Einstellungen. Kapselt Defaults und
/// Parsing, damit der Rest der App nie mit rohen String-Keys hantiert.
class SettingsService {
  static const _keyBackgroundTracking = 'background_tracking_enabled';
  static const _keyRevealRadius = 'reveal_radius_m';
  static const _keyDistanceFilter = 'distance_filter_m';
  static const _keyOnboardingCompleted = 'onboarding_completed';

  static const defaultRevealRadius = 200.0;
  static const defaultDistanceFilter = 50.0;

  Future<bool> isBackgroundTrackingEnabled() async {
    final value = await StorageService.instance.getSetting(_keyBackgroundTracking);
    return value != 'false'; // Standardmäßig aktiviert.
  }

  Future<void> setBackgroundTrackingEnabled(bool enabled) {
    return StorageService.instance.setSetting(_keyBackgroundTracking, '$enabled');
  }

  Future<double> getRevealRadiusMeters() async {
    final value = await StorageService.instance.getSetting(_keyRevealRadius);
    return value != null ? double.parse(value) : defaultRevealRadius;
  }

  Future<void> setRevealRadiusMeters(double meters) {
    return StorageService.instance.setSetting(_keyRevealRadius, '$meters');
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
}
