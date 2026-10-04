import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';

import 'exploration_service.dart';
import 'region_service.dart'; // NEU
import '../regions/breisgau_hochschwarzwald_region.dart'; // NEU

class LocationTaskHandler extends TaskHandler {
  final _exploration = ExplorationService();
  StreamSubscription<Position>? _positionSub;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    RegionService.instance.configure(breisgauHochschwarzwaldRegion); // NEU - eigener Isolate!
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
