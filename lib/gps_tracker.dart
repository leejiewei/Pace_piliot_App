import 'dart:async';

import 'package:geolocator/geolocator.dart';

// FUNCTION 1a - Running pace from GPS.
// Gives the live location (which includes speed) while you run, and can also
// grab a single location (used by the Today screen to get the weather).
class GpsTracker {
  StreamSubscription<Position>? _subscription;

  // Ask for location permission. Returns true if allowed.
  Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  // Get the location just once (e.g. to look up today's weather).
  // Asks for an accurate fresh fix; if that times out (e.g. indoors) it falls
  // back to the last known location so the weather still loads.
  Future<Position> currentLocation() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return last;
      rethrow;
    }
  }

  // Keep getting locations while running. onLocation runs on each new fix.
  void start(void Function(Position location) onLocation) {
    stop();
    const settings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 5,
    );
    _subscription = Geolocator.getPositionStream(locationSettings: settings)
        .listen(onLocation);
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }
}
