import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;

/// Kapselt alle Standort-bezogenen Plattformunterschiede zwischen iOS und
/// Android an einer zentralen Stelle. Der Rest der App arbeitet nur mit
/// dieser Klasse, nie direkt mit `geolocator` oder `permission_handler`.
class LocationService {
  static final LocationService instance = LocationService._internal();
  LocationService._internal();

  StreamSubscription<Position>? _positionSub;
  final _controller = StreamController<Position>.broadcast();

  Stream<Position> get positionStream => _controller.stream;

  /// Schritt 1 des Onboardings: fragt nur "When In Use" an. Auf iOS ist das
  /// Pflicht, bevor "Always" überhaupt angefragt werden darf - ein direkter
  /// Sprung zu "Always" schlägt sonst still fehl.
  Future<LocationPermission> requestWhenInUsePermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission;
  }

  /// Schritt 2 des Onboardings: fragt zusätzlich Hintergrund-Standort an.
  /// Setzt voraus, dass Schritt 1 bereits mindestens "whileInUse" ergeben hat.
  Future<LocationPermissionResult> requestAlwaysPermission() async {
    final current = await Geolocator.checkPermission();

    if (current == LocationPermission.deniedForever) {
      return LocationPermissionResult.deniedForever;
    }
    if (current == LocationPermission.denied) {
      return LocationPermissionResult.whenInUseDenied;
    }
    if (current == LocationPermission.always) {
      return LocationPermissionResult.always;
    }

    final bgStatus = await Permission.locationAlways.request();
    return bgStatus.isGranted
        ? LocationPermissionResult.always
        : LocationPermissionResult.whenInUseOnly;
  }

  /// Für App-Starts NACH abgeschlossenem Onboarding: reiner Status-Check
  /// ohne erneute Erklärungs-UI oder System-Dialoge.
  Future<LocationPermissionResult> checkCurrentStatus() async {
    final permission = await Geolocator.checkPermission();
    switch (permission) {
      case LocationPermission.always:
        return LocationPermissionResult.always;
      case LocationPermission.whileInUse:
        return LocationPermissionResult.whenInUseOnly;
      case LocationPermission.deniedForever:
        return LocationPermissionResult.deniedForever;
      default:
        return LocationPermissionResult.whenInUseDenied;
    }
  }

  /// Startet den Positions-Stream mit einer akkusparenden Konfiguration.
  /// [distanceFilterMeters] kommt aus den Nutzer-Einstellungen (Akku- vs.
  /// Genauigkeits-Trade-off).
  ///
  /// Offener Punkt: aktuell übergibt nur der iOS-Pfad in
  /// ExplorationService.startListening() diesen Parameter nicht explizit
  /// (nutzt also den Default 50m) - der Android-Hintergrundpfad läuft über
  /// einen eigenen Geolocator-Stream im Isolate (background_task_handler.dart)
  /// und liest den Wert bislang ebenfalls nicht aus den Settings.
  Future<void>? _processingChain;

void startTracking({
  Future<void> Function(Position)? onPosition, // war vorher: void Function(Position)?
  double distanceFilterMeters = 50,
}) {
  _positionSub?.cancel();

  final distanceFilter = distanceFilterMeters.round();
  final LocationSettings settings = Platform.isIOS
      ? AppleSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: distanceFilter,
          activityType: ActivityType.other,
          pauseLocationUpdatesAutomatically: false,
          allowBackgroundLocationUpdates: true,
          showBackgroundLocationIndicator: true,
        )
      : LocationSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: distanceFilter,
        );

  _positionSub = Geolocator.getPositionStream(locationSettings: settings).listen((pos) {
    _controller.add(pos);
    // Serialisiert: jeder Aufruf wartet auf den vorherigen, statt parallel
    // zu laufen. Verhindert Race Conditions zwischen recordVisit()-Aufrufen,
    // falls zwei GPS-Fixes kurz hintereinander eintreffen (iOS liefert im
    // Hintergrund/Simulator oft erst einen groben, dann einen präzisen Fix).
    _processingChain = (_processingChain ?? Future.value()).then((_) async {
      await onPosition?.call(pos);
    });
  });
}

  Future<Position> getCurrentPosition() {
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  void stopTracking() {
    _positionSub?.cancel();
    _positionSub = null;
  }

  Future<bool> isLocationServiceEnabled() {
    return Geolocator.isLocationServiceEnabled();
  }

  void dispose() {
    _positionSub?.cancel();
    _controller.close();
  }
}

enum LocationPermissionResult {
  /// Höchste Stufe: Hintergrund-Erkundung funktioniert vollständig.
  always,

  /// Nur Erkundung bei geöffneter/im-Vordergrund-App möglich.
  whenInUseOnly,

  /// Nutzer hat "Nicht erlauben" gewählt - App muss erklären und erneut fragen.
  whenInUseDenied,

  /// Nutzer hat dauerhaft abgelehnt - nur über System-Einstellungen lösbar.
  deniedForever,
}
