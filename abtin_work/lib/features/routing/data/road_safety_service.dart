import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../../core/geo/geo_types.dart';
import 'routing_service.dart';

/// هشدارهای جاده‌ای مستقل از «مسیر انتخاب‌شده».
/// این لایه عمداً جدا از RouteInfo است تا دوربین/سرعت‌گیر/چراغ و محدودیت
/// سرعت هم در حالت بدون مقصد و هم در حالت ناوبری قابل استفاده باشند.
class RoadSafetySnapshot {
  const RoadSafetySnapshot({
    this.alerts = const [],
    this.speedLimitKmh,
    this.roadHeadingDeg,
    this.roadMatchedPosition,
  });

  final List<RouteAlert> alerts;
  final int? speedLimitKmh;
  final double? roadHeadingDeg;
  final LatLng? roadMatchedPosition;
}

class RoadSafetyService {
  RoadSafetyService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  static const String _overpassEndpoint =
      'https://overpass-api.de/api/interpreter';
  static const Duration _requestTimeout = Duration(seconds: 10);

  final http.Client _client;
  final bool _ownsClient;

  DateTime? _lastOnlineRequest;
  LatLng? _lastOnlineCenter;
  RoadSafetySnapshot _onlineCache = const RoadSafetySnapshot();

  Future<RoadSafetySnapshot> online(LatLng center,
      {double radiusM = 450, double? preferredHeadingDeg}) async {
    final lastCenter = _lastOnlineCenter;
    if (_lastOnlineRequest != null &&
        DateTime.now().difference(_lastOnlineRequest!) <
            const Duration(seconds: 20) &&
        lastCenter != null &&
        _distanceM(center, lastCenter) < 120) {
      return _onlineCache;
    }

    final lat = center.latitude.toStringAsFixed(6);
    final lon = center.longitude.toStringAsFixed(6);
    final radius = radiusM.round();
    final query = '''[out:json][timeout:8];
(
  node(around:$radius,$lat,$lon)["highway"="speed_camera"];
  node(around:$radius,$lat,$lon)["enforcement"="maxspeed"];
  node(around:$radius,$lat,$lon)["traffic_calming"];
  node(around:$radius,$lat,$lon)["highway"="traffic_signals"];
  node(around:$radius,$lat,$lon)["amenity"="police"];
  way(around:$radius,$lat,$lon)["highway"];
);
out geom;''';

    try {
      final response = await _client.post(
        Uri.parse(_overpassEndpoint),
        headers: const {
          'User-Agent': 'AbtinMaps/0.1 (road-safety)',
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'Accept': 'application/json',
        },
        body: {'data': query},
      ).timeout(_requestTimeout);
      if (response.statusCode != 200) return _onlineCache;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return _onlineCache;
      final elements = decoded['elements'];
      if (elements is! List) return _onlineCache;

      final alerts = <RouteAlert>[];
      final speedCandidates = <({int speed, double distance})>[];
      final headingCandidates = <({double heading, double distance})>[];
      ({LatLng point, double distance, double heading})? nearestRoad;
      for (final raw in elements) {
        if (raw is! Map) continue;
        final e = Map<String, dynamic>.from(raw);
        final tags = e['tags'] is Map
            ? Map<String, dynamic>.from(e['tags'] as Map)
            : const <String, dynamic>{};
        final point = _elementPoint(e);
        if (point == null) continue;
        final distance = _distanceM(center, point);

        final highway = tags['highway']?.toString();
        final calming = tags['traffic_calming']?.toString();
        final amenity = tags['amenity']?.toString();
        final enforcement = tags['enforcement']?.toString();
        if (highway == 'speed_camera' || enforcement == 'maxspeed') {
          alerts.add(RouteAlert(
            type: RouteAlertType.speedCamera,
            location: point,
            name: tags['name:fa']?.toString() ?? tags['name']?.toString(),
          ));
        } else if (calming != null) {
          alerts.add(RouteAlert(
            type: RouteAlertType.speedBump,
            location: point,
            name: tags['name:fa']?.toString() ?? tags['name']?.toString(),
          ));
        } else if (highway == 'traffic_signals') {
          alerts.add(RouteAlert(
            type: RouteAlertType.trafficLight,
            location: point,
            name: tags['name:fa']?.toString() ?? tags['name']?.toString(),
          ));
        } else if (amenity == 'police') {
          alerts.add(RouteAlert(
            type: RouteAlertType.policeCheckpoint,
            location: point,
            name: tags['name:fa']?.toString() ?? tags['name']?.toString(),
          ));
        }

        final geometry = e['geometry'];
        var wayDistance = distance;
        if (geometry is List && geometry.length >= 2) {
          for (var i = 1; i < geometry.length; i++) {
            final ga = geometry[i - 1];
            final gb = geometry[i];
            if (ga is! Map || gb is! Map) continue;
            final a = _elementPoint(Map<String, dynamic>.from(ga));
            final b = _elementPoint(Map<String, dynamic>.from(gb));
            if (a == null || b == null) continue;
            final segmentDistance = _distanceToSegmentM(center, a, b);
            wayDistance = math.min(wayDistance, segmentDistance);
            final bearing = _bearing(a, b);
            headingCandidates
                .add((heading: bearing, distance: segmentDistance));
            if (nearestRoad == null || segmentDistance < nearestRoad.distance) {
              final projected = _projectSegment(center, a, b);
              nearestRoad = (
                point: projected.point,
                distance: segmentDistance,
                heading: bearing,
              );
            }
          }
        }
        final speed = _parseSpeed(tags['maxspeed']);
        if (speed != null) {
          speedCandidates.add((speed: speed, distance: wayDistance));
        }
      }
      speedCandidates.sort((a, b) => a.distance.compareTo(b.distance));
      final roadHeading =
          _chooseHeading(headingCandidates, preferredHeadingDeg);
      alerts.sort((a, b) => _distanceM(center, a.location)
          .compareTo(_distanceM(center, b.location)));
      final uniqueAlerts = <RouteAlert>[];
      for (final alert in alerts) {
        if (uniqueAlerts.every((x) =>
            x.type != alert.type ||
            _distanceM(x.location, alert.location) > 12)) {
          uniqueAlerts.add(alert);
        }
      }
      _onlineCache = RoadSafetySnapshot(
        alerts: List.unmodifiable(uniqueAlerts),
        speedLimitKmh:
            speedCandidates.isEmpty ? null : speedCandidates.first.speed,
        roadHeadingDeg: roadHeading,
        roadMatchedPosition: nearestRoad != null && nearestRoad.distance <= 35.0
            ? nearestRoad.point
            : null,
      );
      _lastOnlineCenter = center;
      _lastOnlineRequest = DateTime.now();
      return _onlineCache;
    } catch (_) {
      return _onlineCache;
    }
  }

  LatLng? _elementPoint(Map<String, dynamic> e) {
    final lat = _asDouble(e['lat']);
    final lon = _asDouble(e['lon']);
    if (lat != null && lon != null) return LatLng(lat, lon);
    final center = e['center'];
    if (center is Map) {
      final c = Map<String, dynamic>.from(center);
      final clat = _asDouble(c['lat']);
      final clon = _asDouble(c['lon']);
      if (clat != null && clon != null) return LatLng(clat, clon);
    }
    return null;
  }

  /// Offline road-safety data (speed cameras, bumps, signals, speed limit
  /// matched to the nearest road) came from reading the local .abm file.
  /// Offline reading has been removed from the app, so this always returns
  /// an empty snapshot instead of pretending to read anything.
  Future<RoadSafetySnapshot> offline(
    File mapFile,
    LatLng center, {
    double radiusM = 450,
    double? preferredHeadingDeg,
  }) async {
    return const RoadSafetySnapshot();
  }

  int? _parseSpeed(Object? value) {
    if (value == null) return null;
    final raw = value.toString().trim().toLowerCase();
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(raw);
    if (match == null) return null;
    final n = double.tryParse(match.group(1)!);
    if (n == null || !n.isFinite || n <= 0 || n > 250) return null;
    final kmh = raw.contains('mph') ? n * 1.609344 : n;
    return kmh.round().clamp(5, 250);
  }

  double? _asDouble(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value');

  double _distanceM(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final aa = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(a.latitude * math.pi / 180) *
            math.cos(b.latitude * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(aa), math.sqrt(1 - aa));
  }

  double _distanceToSegmentM(LatLng p, LatLng a, LatLng b) {
    final latRad = p.latitude * math.pi / 180;
    final mx = 111320.0 * math.cos(latRad);
    final ax = (a.longitude - p.longitude) * mx;
    final ay = (a.latitude - p.latitude) * 110540.0;
    final bx = (b.longitude - p.longitude) * mx;
    final by = (b.latitude - p.latitude) * 110540.0;
    final dx = bx - ax;
    final dy = by - ay;
    final len = dx * dx + dy * dy;
    if (len < 1e-9) return math.sqrt(ax * ax + ay * ay);
    final t = (-(ax * dx + ay * dy) / len).clamp(0.0, 1.0);
    final x = ax + dx * t;
    final y = ay + dy * t;
    return math.sqrt(x * x + y * y);
  }

  ({LatLng point, double t}) _projectSegment(LatLng p, LatLng a, LatLng b) {
    final latRad = p.latitude * math.pi / 180;
    final mx = 111320.0 * math.cos(latRad);
    const my = 110540.0;
    final ax = (a.longitude - p.longitude) * mx;
    final ay = (a.latitude - p.latitude) * my;
    final bx = (b.longitude - p.longitude) * mx;
    final by = (b.latitude - p.latitude) * my;
    final dx = bx - ax;
    final dy = by - ay;
    final len2 = dx * dx + dy * dy;
    final t = len2 <= 1e-9
        ? 0.0
        : (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0).toDouble();
    return (
      point: LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      ),
      t: t,
    );
  }

  double? _chooseHeading(
      List<({double heading, double distance})> candidates, double? preferred) {
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => a.distance.compareTo(b.distance));
    if (preferred == null || !preferred.isFinite)
      return candidates.first.heading;
    final nearest = candidates.take(12).toList(growable: false);
    ({double heading, double distance})? best;
    var bestScore = double.infinity;
    for (final c in nearest) {
      final d = _angleDistance(c.heading, preferred);
      // Prefer a physically close road, but use GPS direction to choose the
      // correct direction on a two-way road. Both directions are equivalent
      // for the camera, so compare the 180-degree equivalent too.
      final score = c.distance + math.min(d, (180.0 - d).abs()) * 1.8;
      if (score < bestScore) {
        bestScore = score;
        best = c;
      }
    }
    return best?.heading;
  }

  double _angleDistance(double a, double b) {
    final d = ((a - b + 540) % 360) - 180;
    return d.abs();
  }

  double _bearing(LatLng a, LatLng b) {
    final y = (b.longitude - a.longitude) *
        math.cos((a.latitude + b.latitude) * math.pi / 360.0);
    final x = b.latitude - a.latitude;
    return (math.atan2(y, x) * 180.0 / math.pi + 360.0) % 360.0;
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
