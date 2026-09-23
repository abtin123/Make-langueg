import 'package:flutter/foundation.dart';

/// نوع‌های هندسی داخلی آبتین‌مپ برای routing، search و catalog دادهٔ آفلاین.
/// renderer نقشه از MapLibre Native استفاده می‌کند و controller آن اینجا تعریف
/// نمی‌شود.
@immutable
class LatLng {
  const LatLng(this.latitude, this.longitude);
  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is LatLng &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

@immutable
class LatLngBounds {
  const LatLngBounds({required this.southwest, required this.northeast});
  final LatLng southwest;
  final LatLng northeast;
}

@immutable
class CameraPosition {
  const CameraPosition({
    required this.target,
    required this.zoom,
    this.bearing = 0,
    this.tilt = 0,
  });
  final LatLng target;
  final double zoom;
  final double bearing;
  final double tilt;
}
