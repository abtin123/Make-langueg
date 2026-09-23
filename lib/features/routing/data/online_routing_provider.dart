import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../../core/geo/geo_types.dart';
import 'routing_instruction_localizer.dart';
import '../../../core/localization/app_localizations.dart';
import 'routing_provider.dart';
import 'routing_service.dart';

/// پیاده‌سازی مسیریابی برخط بر پایهٔ API سازگار با OSRM.
///
/// endpoint به‌صورت constructor injection است تا نسخهٔ عملیاتی بتواند به
/// سرویس اختصاصی/قراردادی منتقل شود؛ endpoint عمومی پیش‌فرض فقط برای توسعه و
/// استفادهٔ سبک تعاملی مناسب است. هیچ مختصات مکانی در حافظه ذخیره نمی‌شود و
/// درخواست فقط پس از انتخاب صریح مقصد توسط کاربر ارسال می‌شود.
class OnlineRoutingProvider implements RoutingProvider {
  OnlineRoutingProvider({
    http.Client? client,
    this.endpoint = defaultEndpoint,
    this.requestTimeout = const Duration(seconds: 12),
    this.languageCode = _defaultLanguageCode,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null;

  /// endpoint پیش‌فرضِ قابل جایگزینی. برای تولید پرترافیک باید OSRM اختصاصی
  /// یا سرویس دارای قرارداد جایگزین شود.
  static const String defaultEndpoint = 'https://router.project-osrm.org';
  static String _defaultLanguageCode() => 'fa';

  final http.Client _client;
  final bool _ownsClient;
  final String endpoint;
  final Duration requestTimeout;
  final String Function() languageCode;

  @override
  RoutingEngine get engine => RoutingEngine.online;

  @override
  String get displayName => 'نقشه و مسیریابی آنلاین';

  @override
  bool get isOffline => false;

  @override
  String? lastError;

  @override
  Future<bool> isReady() async => true;

  @override
  Future<RouteInfo?> calculateRoute({
    required LatLng origin,
    required LatLng destination,
    bool offlineOnly = false,
  }) async {
    final routes = await calculateRoutes(
      origin: origin,
      destination: destination,
      offlineOnly: offlineOnly,
    );
    return routes.isEmpty ? null : routes.first;
  }

  Future<List<RouteInfo>> calculateRoutes({
    required LatLng origin,
    required LatLng destination,
    bool offlineOnly = false,
  }) async {
    lastError = null;
    if (offlineOnly) {
      lastError = AppStrings.getForLanguage(
          languageCode(), 'route_error_offline_unavailable');
      return const [];
    }
    if (!_isValidCoordinate(origin) || !_isValidCoordinate(destination)) {
      lastError = AppStrings.getForLanguage(
          languageCode(), 'route_error_invalid_coordinates');
      return const [];
    }

    final coordinates =
        '${origin.longitude.toStringAsFixed(6)},${origin.latitude.toStringAsFixed(6)};'
        '${destination.longitude.toStringAsFixed(6)},${destination.latitude.toStringAsFixed(6)}';
    final base = endpoint.endsWith('/')
        ? endpoint.substring(0, endpoint.length - 1)
        : endpoint;
    final uri = Uri.parse('$base/route/v1/driving/$coordinates').replace(
      queryParameters: const {
        'alternatives': 'true',
        'steps': 'true',
        'geometries': 'geojson',
        'overview': 'full',
      },
    );

    try {
      final response = await _client.get(
        uri,
        headers: const {
          // شناسهٔ شفاف برای سرویس‌های مبتنی بر OSM؛ از جعل User-Agent
          // مرورگر اجتناب شده است.
          'User-Agent': 'AbtinMaps/0.1 (online-routing)',
          'Accept': 'application/json',
        },
      ).timeout(requestTimeout);
      if (response.statusCode != 200) {
        lastError =
            AppStrings.getForLanguage(languageCode(), 'route_error_http')
                .replaceAll('{code}', '${response.statusCode}');
        return const [];
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        lastError = AppStrings.getForLanguage(
            languageCode(), 'route_error_unreadable_response');
        return const [];
      }
      if (decoded['code'] != 'Ok') {
        lastError =
            _osrmErrorMessage(decoded['code']?.toString(), languageCode());
        return const [];
      }
      final routesJson = decoded['routes'];
      if (routesJson is! List || routesJson.isEmpty) {
        lastError = AppStrings.getForLanguage(
            languageCode(), 'route_error_online_not_found');
        return const [];
      }

      final routes = <RouteInfo>[];
      for (final routeJson in routesJson) {
        if (routeJson is! Map) continue;
        final route = _parseRoute(Map<String, dynamic>.from(routeJson));
        if (route != null) routes.add(route);
      }
      if (routes.isEmpty) {
        lastError = AppStrings.getForLanguage(
            languageCode(), 'route_error_invalid_geometry');
      }
      return routes;
    } on TimeoutException {
      lastError =
          AppStrings.getForLanguage(languageCode(), 'route_error_timeout');
      return const [];
    } on FormatException {
      lastError = AppStrings.getForLanguage(
          languageCode(), 'route_error_invalid_response');
      return const [];
    } on http.ClientException {
      lastError =
          AppStrings.getForLanguage(languageCode(), 'route_error_connection');
      return const [];
    } catch (_) {
      lastError =
          AppStrings.getForLanguage(languageCode(), 'route_error_unexpected');
      return const [];
    }
  }

  RouteInfo? _parseRoute(Map<String, dynamic> route) {
    final geometry = route['geometry'];
    if (geometry is! Map) return null;
    final coordinates = geometry['coordinates'];
    if (coordinates is! List) return null;

    final points = <LatLng>[];
    for (final coordinate in coordinates) {
      if (coordinate is! List || coordinate.length < 2) continue;
      final lng = _asDouble(coordinate[0]);
      final lat = _asDouble(coordinate[1]);
      if (lat == null || lng == null || !lat.isFinite || !lng.isFinite)
        continue;
      points.add(LatLng(lat, lng));
    }
    if (points.length < 2) return null;

    final distanceM = _asDouble(route['distance']) ?? 0;
    final durationS = _asDouble(route['duration']) ?? 0;
    return RouteInfo(
      geometry: points,
      distanceKm: distanceM / 1000,
      durationMin: durationS / 60,
      instructions: _parseInstructions(route['legs'], languageCode()),
    );
  }

  List<RouteInstruction> _parseInstructions(
      Object? legsJson, String languageCode) {
    if (legsJson is! List) return const [];
    final instructions = <RouteInstruction>[];
    for (final legJson in legsJson) {
      if (legJson is! Map) continue;
      final stepsJson = legJson['steps'];
      if (stepsJson is! List) continue;
      for (final stepJson in stepsJson) {
        if (stepJson is! Map) continue;
        final step = Map<String, dynamic>.from(stepJson);
        final maneuver = step['maneuver'];
        if (maneuver is! Map) continue;
        final maneuverMap = Map<String, dynamic>.from(maneuver);
        final location = maneuverMap['location'];
        if (location is! List || location.length < 2) continue;
        final lng = _asDouble(location[0]);
        final lat = _asDouble(location[1]);
        if (lat == null || lng == null || !lat.isFinite || !lng.isFinite)
          continue;
        final rawType = maneuverMap['type']?.toString() ?? 'turn';
        final rawModifier = maneuverMap['modifier']?.toString();
        final exit = maneuverMap['exit'] is num
            ? (maneuverMap['exit'] as num).toInt()
            : null;
        final geometryPoints = _stepCoordinates(step);
        final inferredModifier = _normalizedOnlineModifier(
          type: rawType,
          modifier: rawModifier,
          geometry: geometryPoints,
        );
        final type = inferredModifier == 'uturn' ? 'uturn' : rawType;
        final modifier = inferredModifier;
        final roadName = step['name']?.toString().trim();
        LatLng? maneuverEndLocation;
        if (geometryPoints.isNotEmpty) {
          maneuverEndLocation = geometryPoints.last;
        }

        final roundabout = (rawType == 'roundabout' || rawType == 'rotary')
            ? _analyzeOnlineRoundabout(step, maneuverMap, geometryPoints)
            : const _OnlineRoundaboutData.empty();
        instructions.add(
          RouteInstruction(
            text: _instructionText(
              type: type,
              modifier: modifier,
              roadName: roadName?.isEmpty ?? true ? null : roadName,
              exit: exit,
              languageCode: languageCode,
            ),
            distanceMeters: _asDouble(step['distance']) ?? 0,
            location: LatLng(lat, lng),
            type: type,
            modifier: modifier,
            exit: exit,
            roundaboutExitCount: roundabout.exitCount,
            roundaboutBranchAngles: roundabout.branchAngles,
            roundaboutEntranceAngles: roundabout.entranceAngles,
            roundaboutExitAngles: roundabout.exitAngles,
            roundaboutActiveExitAngle: roundabout.activeExitAngle,
            maneuverEndLocation: maneuverEndLocation,
          ),
        );
      }
    }
    return instructions;
  }


  List<LatLng> _stepCoordinates(Map<String, dynamic> step) {
    final geometry = step['geometry'];
    if (geometry is! Map) return const [];
    final coordinates = geometry['coordinates'];
    if (coordinates is! List) return const [];
    final out = <LatLng>[];
    for (final raw in coordinates) {
      if (raw is! List || raw.length < 2) continue;
      final lng = _asDouble(raw[0]);
      final lat = _asDouble(raw[1]);
      if (lat == null || lng == null || !lat.isFinite || !lng.isFinite) continue;
      out.add(LatLng(lat, lng));
    }
    return out;
  }

  String? _normalizedOnlineModifier({
    required String type,
    required String? modifier,
    required List<LatLng> geometry,
  }) {
    final normalized = (modifier ?? '')
        .trim()
        .toLowerCase()
        .replaceAll('-', ' ')
        .replaceAll('_', ' ');
    if (type == 'roundabout' || type == 'rotary') return modifier;
    if (normalized.contains('uturn') || normalized.contains('u turn')) {
      return 'uturn';
    }
    if (geometry.length >= 4 &&
        (type == 'turn' || type == 'continue' || type == 'new name' || type == 'end of road')) {
      final firstEnd = math.min(geometry.length - 1, 2);
      final lastStart = math.max(0, geometry.length - 3);
      final first = _bearing(geometry[0], geometry[firstEnd]);
      final last = _bearing(geometry[lastStart], geometry.last);
      final delta = _signedAngle(last - first).abs();
      if (delta >= 150) return 'uturn';
    }
    final inferred = _inferShallowModifier(geometry);
    // OSRM can legitimately report `straight` for a very shallow branch.
    // Prefer the actual step geometry for these small-angle exits so ramps,
    // underpasses and main-street branches are not rendered as a dead-straight
    // arrow. Strong left/right/sharp modifiers from the router remain intact.
    if (inferred != null &&
        (normalized.isEmpty || normalized == 'straight') &&
        inferred != 'straight') {
      return inferred;
    }
    if (modifier == null || normalized.isEmpty) return inferred;
    return modifier;
  }

  String? _inferShallowModifier(List<LatLng> geometry) {
    if (geometry.length < 4) return null;
    final firstEnd = math.min(geometry.length - 1, 2);
    final lastStart = math.max(0, geometry.length - 3);
    final first = _bearing(geometry[0], geometry[firstEnd]);
    final last = _bearing(geometry[lastStart], geometry.last);
    final delta = _signedAngle(last - first);
    final a = delta.abs();
    if (a >= 150) return 'uturn';
    if (a >= 55) return delta > 0 ? 'right' : 'left';
    if (a >= 5) return delta > 0 ? 'slight right' : 'slight left';
    return 'straight';
  }

  double _bearing(LatLng a, LatLng b) {
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dl = (b.longitude - a.longitude) * math.pi / 180;
    final y = math.sin(dl) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dl);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  double _signedAngle(double angle) {
    var a = angle % 360;
    if (a > 180) a -= 360;
    if (a < -180) a += 360;
    return a;
  }

  _OnlineRoundaboutData _analyzeOnlineRoundabout(
    Map<String, dynamic> step,
    Map<String, dynamic> maneuver,
    List<LatLng> geometry,
  ) {
    final rawIntersections = step['intersections'];
    if (rawIntersections is! List) {
      return const _OnlineRoundaboutData.empty();
    }

    final angles = <double>[];
    final entrances = <double>[];
    final exits = <double>[];
    double? activeExit;

    void addUnique(List<double> target, double value) {
      final normalized = (value % 360 + 360) % 360;
      for (final old in target) {
        var d = (old - normalized).abs();
        if (d > 180) d = 360 - d;
        if (d <= 7.5) return;
      }
      target.add(normalized);
    }

    for (var i = 0; i < rawIntersections.length; i++) {
      final raw = rawIntersections[i];
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final bearings = m['bearings'];
      if (bearings is! List || bearings.isEmpty) continue;
      final entry = m['entry'] is List ? List<dynamic>.from(m['entry']) : const <dynamic>[];
      final inIndex = m['in'] is num ? (m['in'] as num).toInt() : -1;
      final outIndex = m['out'] is num ? (m['out'] as num).toInt() : -1;

      // At the first node, `in` is the physical entrance arm. At the last
      // node, `out` is the physical exit arm. At intermediate nodes every
      // bearing other than the two roundabout travel bearings is a physical
      // arm. This mirrors the topology-based offline reader instead of
      // assuming four branches.
      if (i == 0 && inIndex >= 0 && inIndex < bearings.length) {
        final b = _asDouble(bearings[inIndex]);
        if (b != null) {
          addUnique(angles, b);
          addUnique(entrances, b);
        }
      }

      for (var j = 0; j < bearings.length; j++) {
        if (j == inIndex || j == outIndex) continue;
        final b = _asDouble(bearings[j]);
        if (b == null) continue;
        final canExit = j < entry.length ? entry[j] == true : true;
        addUnique(angles, b);
        if (canExit) addUnique(exits, b);
        if (j < entry.length && entry[j] == true) addUnique(entrances, b);
      }

      if (i == rawIntersections.length - 1 && outIndex >= 0 && outIndex < bearings.length) {
        final b = _asDouble(bearings[outIndex]);
        if (b != null) {
          addUnique(angles, b);
          addUnique(exits, b);
          activeExit = (maneuver['exit'] is num || geometry.length >= 2) ? b : activeExit;
        }
      }
    }

    // Some OSRM profiles omit intersections on very short roundabouts. The
    // step geometry still gives us the actual exit direction, so never leave
    // the main branch as a fake straight line in that case.
    if (activeExit == null && geometry.length >= 2) {
      activeExit = _bearing(geometry[geometry.length - 2], geometry.last);
      addUnique(angles, activeExit);
      addUnique(exits, activeExit);
    }

    final maneuverExit = maneuver['exit'] is num
        ? (maneuver['exit'] as num).toInt()
        : null;
    final orderedExits = [...exits];
    final exitCount = orderedExits.length;
    if (angles.length < 2) return const _OnlineRoundaboutData.empty();

    return _OnlineRoundaboutData(
      exitCount: exitCount == 0 ? maneuverExit : exitCount,
      branchAngles: List.unmodifiable(angles),
      entranceAngles: List.unmodifiable(entrances),
      exitAngles: List.unmodifiable(exits),
      activeExitAngle: activeExit,
    );
  }

  String _instructionText({
    required String type,
    required String? modifier,
    required String? roadName,
    required int? exit,
    required String languageCode,
  }) =>
      RoutingInstructionLocalizer.text(
        languageCode: languageCode,
        type: type,
        modifier: modifier,
        roadName: roadName,
        exit: exit,
      );

  String _osrmErrorMessage(String? code, String languageCode) => switch (code) {
        'NoRoute' => AppStrings.getForLanguage(
            languageCode, 'route_error_online_not_found'),
        'NoSegment' =>
          AppStrings.getForLanguage(languageCode, 'route_error_no_segment'),
        'TooBig' =>
          AppStrings.getForLanguage(languageCode, 'route_error_too_big'),
        _ =>
          AppStrings.getForLanguage(languageCode, 'route_error_online_failed'),
      };

  bool _isValidCoordinate(LatLng point) =>
      point.latitude.isFinite &&
      point.longitude.isFinite &&
      point.latitude.abs() <= 90 &&
      point.longitude.abs() <= 180;

  double? _asDouble(Object? value) => value is num ? value.toDouble() : null;

  void dispose() {
    if (_ownsClient) _client.close();
  }
}

class _OnlineRoundaboutData {
  const _OnlineRoundaboutData({
    required this.exitCount,
    required this.branchAngles,
    required this.entranceAngles,
    required this.exitAngles,
    required this.activeExitAngle,
  });

  const _OnlineRoundaboutData.empty()
      : exitCount = null,
        branchAngles = const [],
        entranceAngles = const [],
        exitAngles = const [],
        activeExitAngle = null;

  final int? exitCount;
  final List<double> branchAngles;
  final List<double> entranceAngles;
  final List<double> exitAngles;
  final double? activeExitAngle;
}

