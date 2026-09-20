import 'dart:async';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

import 'exploration_service.dart';

/// Läuft in einem separaten Isolate und bleibt aktiv, solange der Android
/// Foreground Service läuft - auch wenn die App minimiert oder aus der
/// App-Übersicht entfernt wurde (siehe Plattform-Einschränkungen im README).
///
/// Wichtig: Dieser Isolate hat keinen Zugriff auf den UI-State. Deshalb hat
/// er eine eigene ExplorationService-Instanz und schreibt direkt in SQLite.
/// Neu erkundete Zellen werden zusätzlich per `sendDataToMain` an die UI
/// gemeldet, damit die Karte live aktualisiert, falls die App sichtbar ist.
/// Achievements, die hier freigeschaltet werden, laufen NICHT automatisch
/// zur UI durch - die UI-Seite prüft nach jedem Datenempfang zusätzlich
/// selbst gegen den DB-Stand (siehe HomeScreen._checkAchievementsAfterBackgroundUpdate).
class LocationTaskHandler extends TaskHandler {
  final _exploration = ExplorationService();
  StreamSubscription<Position>? _positionSub;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _exploration.init();

    const settings = LocationSettings(
      accuracy: LocationAccuracy.medium,
      distanceFilter: 50,
    );

    _positionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen((position) async {
      await _exploration.recordVisit(position.latitude, position.longitude);

      FlutterForegroundTask.sendDataToMain({
        'lat': position.latitude,
        'lng': position.longitude,
      });

      FlutterForegroundTask.updateService(
        notificationTitle: 'XploreD',
        notificationText:
            '${_exploration.totalExploredCount} Gebiete erkundet',
      );
    });
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Nicht genutzt - wir reagieren event-basiert auf den Position-Stream,
    // nicht auf ein festes Zeitintervall. Pflicht-Override der TaskHandler-API.
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    await _positionSub?.cancel();
    _exploration.dispose();
  }
}

/// Muss als globale/top-level Funktion existieren - wird vom Foreground-
/// Service-Isolate beim Start aufgerufen (Vorgabe des Plugins).
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(LocationTaskHandler());
}
