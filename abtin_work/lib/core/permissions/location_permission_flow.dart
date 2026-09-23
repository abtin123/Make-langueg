import 'package:geolocator/geolocator.dart';

enum LocationReadiness {
  ready,
  permissionDenied,
  permissionDeniedForever,
  serviceDisabled
}

class LocationPermissionFlow {
  static Future<LocationReadiness> ensureReady() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return LocationReadiness.serviceDisabled;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return LocationReadiness.permissionDenied;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return LocationReadiness.permissionDeniedForever;
    }

    return LocationReadiness.ready;
  }

  static Future<LocationReadiness> checkStatus() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return LocationReadiness.serviceDisabled;

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      return LocationReadiness.permissionDenied;
    }
    if (permission == LocationPermission.deniedForever) {
      return LocationReadiness.permissionDeniedForever;
    }
    return LocationReadiness.ready;
  }

  static Future<LocationReadiness> checkStatusAndRetryIfDenied() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return LocationReadiness.serviceDisabled;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return LocationReadiness.permissionDenied;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return LocationReadiness.permissionDeniedForever;
    }
    return LocationReadiness.ready;
  }

  static Future<LocationReadiness> retryFromUserTap() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      return LocationReadiness.permissionDeniedForever;
    }
    return checkStatusAndRetryIfDenied();
  }
}
