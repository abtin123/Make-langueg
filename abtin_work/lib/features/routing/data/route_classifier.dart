import 'package:abtin_maps/core/geo/geo_types.dart';
import '../../offline_maps/data/iran_provinces.dart';
import 'dart:math';

enum RouteType {
  urban,
  interCity,
  interProvince,
}

class RouteClassifier {
  static const double _urbanDistanceThresholdKm =
      15.0; // Distance to consider a route urban

  RouteType classifyRoute(LatLng origin, LatLng destination) {
    final originProvince = getProvinceForLatLng(origin);
    final destinationProvince = getProvinceForLatLng(destination);

    if (originProvince == null || destinationProvince == null) {
      // If either point is outside known provinces, default to inter-province or a general graph
      // For now, we'll assume a national graph will handle this.
      return RouteType.interProvince;
    }

    if (originProvince.id != destinationProvince.id) {
      return RouteType.interProvince;
    } else {
      // Same province, check distance for urban vs inter-city
      final distance = haversine(origin, destination) / 1000; // distance in km
      if (distance <= _urbanDistanceThresholdKm) {
        return RouteType.urban;
      } else {
        return RouteType.interCity;
      }
    }
  }

  Province? getProvinceForLatLng(LatLng coord) {
    for (final province in kIranProvinces) {
      if (coord.latitude >= province.bounds.southwest.latitude &&
          coord.latitude <= province.bounds.northeast.latitude &&
          coord.longitude >= province.bounds.southwest.longitude &&
          coord.longitude <= province.bounds.northeast.longitude) {
        return province;
      }
    }
    return null;
  }

  double haversine(LatLng a, LatLng b) {
    const r = 6371000.0; // Earth's radius in meters
    final dLat = (b.latitude - a.latitude) * pi / 180;
    final dLng = (b.longitude - a.longitude) * pi / 180;
    final la1 = a.latitude * pi / 180;
    final la2 = b.latitude * pi / 180;
    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(la1) * cos(la2) * sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * atan2(sqrt(h), sqrt(1 - h));
  }
}
