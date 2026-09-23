import 'dart:math' as math;

import '../../../core/abm_debug_log.dart';
import '../../../core/geo/geo_types.dart';
import '../../../abtinmap/abm_map_service.dart';
import '../../../routing/routing_engine.dart' as routing_engine_lib;
import '../../offline_maps/data/vector_map_service.dart';
import 'routing_provider.dart';
import 'routing_service.dart';
import 'routing_instruction_localizer.dart';

/// Offline routing reader for the canonical ABM map.sqlite graph.
class AbtinmapRoutingProvider implements RoutingProvider {
  AbtinmapRoutingProvider({
    required AbmMapService mapService,
    required VectorMapService vectorMapService,
    this.mapName = 'IR.abm',
    this.languageCode = _defaultLanguageCode,
  })  : _mapService = mapService,
        _vectorMaps = vectorMapService;

  final AbmMapService _mapService;
  final String mapName;
  final String Function() languageCode;
  static String _defaultLanguageCode() => 'fa';
  final routing_engine_lib.AbmRoutingEngine _engine = routing_engine_lib.AbmRoutingEngine();
  final VectorMapService _vectorMaps;
  String? _lastError;

  @override
  RoutingEngine get engine => RoutingEngine.abtinmap;
  @override
  String get displayName => 'آبتین‌مپ (آفلاین)';
  @override
  bool get isOffline => true;
  @override
  String? get lastError => _lastError;

  @override
  Future<bool> isReady() async {
    try {
      final file = await _mapService.localFile(mapName);
      final exists = await file.exists();
      final size = exists ? await file.length() : 0;
      await AbmDebugLog.addRouting('READY map=$mapName path=${file.path} exists=$exists bytes=$size');
      if (!exists || size == 0) {
        _lastError = 'نقشهٔ آفلاین نصب نشده است.';
        await AbmDebugLog.addRouting('READY ERROR map_missing');
        return false;
      }
      // Read/validate the canonical SQLite payload before declaring routing
      // ready. This also repairs legacy caches that were marked valid before
      // integrity/graph validation completed.
      final id = mapName.toLowerCase().endsWith('.abm')
          ? mapName.substring(0, mapName.length - 4)
          : mapName;
      final artifacts = await _vectorMaps.prepare(containerFile: file, id: id);
      await AbmDebugLog.addRouting(
        'READY SQLITE path=${artifacts.sqliteFile.path} bytes=${await artifacts.sqliteFile.length()}',
      );
      _lastError = null;
      return true;
    } catch (error, stack) {
      _lastError = 'نقشهٔ آفلاین قابل استفاده نیست.';
      await AbmDebugLog.addRouting('READY ERROR error=$error\n$stack');
      return false;
    }
  }

  @override
  Future<RouteInfo?> calculateRoute({
    required LatLng origin,
    required LatLng destination,
    bool offlineOnly = false,
    bool avoidUnpavedRoads = false,
    bool avoidTolls = false,
  }) async {
    _lastError = null;
    await AbmDebugLog.addRouting(
      'START map=$mapName offlineOnly=$offlineOnly '
      'origin=${origin.latitude.toStringAsFixed(6)},${origin.longitude.toStringAsFixed(6)} '
      'destination=${destination.latitude.toStringAsFixed(6)},${destination.longitude.toStringAsFixed(6)} '
      'avoidUnpaved=$avoidUnpavedRoads avoidTolls=$avoidTolls',
    );
    try {
      final container = await _mapService.localFile(mapName);
      final exists = await container.exists();
      final size = exists ? await container.length() : 0;
      await AbmDebugLog.addRouting('MAP file=${container.path} exists=$exists bytes=$size');
      if (!exists || size == 0) {
        _lastError = 'نقشهٔ آفلاین نصب نشده است.';
        await AbmDebugLog.addRouting('ERROR map_missing');
        return null;
      }
      final id = mapName.toLowerCase().endsWith('.abm')
          ? mapName.substring(0, mapName.length - 4)
          : mapName;
      await AbmDebugLog.addRouting('PREPARE begin id=$id');
      final artifacts = await _vectorMaps.prepare(containerFile: container, id: id);
      await AbmDebugLog.addRouting(
        'PREPARE done sqlite=${artifacts.sqliteFile.path} sqliteBytes=${await artifacts.sqliteFile.length()} '
        'metadataKeys=${artifacts.metadata.keys.length}',
      );
      await AbmDebugLog.addRouting('ENGINE begin sqlite=${artifacts.sqliteFile.path}');
      final result = await _engine.routeDetailed(
        artifacts.sqliteFile,
        routing_engine_lib.RoutePoint(origin.latitude, origin.longitude),
        routing_engine_lib.RoutePoint(destination.latitude, destination.longitude),
        avoidUnpavedRoads: avoidUnpavedRoads,
        avoidTolls: avoidTolls,
      );
      if (result == null) {
        _lastError = 'برای این مبدأ و مقصد مسیر قابل دسترسی پیدا نشد.';
        await AbmDebugLog.addRouting('ENGINE END null lastError=$_lastError');
        return null;
      }
      for (final line in result.diagnostics) {
        await AbmDebugLog.addRouting(line);
      }
      for (var i = 0; i < result.edges.length; i++) {
        final e = result.edges[i];
        await AbmDebugLog.addRouting(
          'EDGE[$i] from=${e.from.lat.toStringAsFixed(6)},${e.from.lon.toStringAsFixed(6)} '
          'to=${e.to.lat.toStringAsFixed(6)},${e.to.lon.toStringAsFixed(6)} '
          'way=${e.wayId} class=${e.roadClass} name="${e.name}" junction=${e.junction} '
          'speed=${e.speedKmh ?? '-'} roundaboutExit=${e.roundaboutExitNumber ?? '-'}',
        );
      }
      if (result.points.length < 2) {
        _lastError = 'برای این مبدأ و مقصد مسیر قابل دسترسی پیدا نشد.';
        await AbmDebugLog.addRouting('ERROR geometry_too_short points=${result.points.length}');
        return null;
      }
      final geometry = result.points
          .map((p) => LatLng(p.lat, p.lon))
          .toList(growable: false);
      final distanceKm = _distanceKm(result.points);
      final durationMin = _estimateDurationMinutes(result);
      final instructions = _buildInstructions(result, geometry);
      await AbmDebugLog.addRouting(
        'END success points=${geometry.length} edges=${result.edges.length} '
        'distanceKm=${distanceKm.toStringAsFixed(3)} durationMin=${durationMin.toStringAsFixed(2)} instructions=${instructions.length}',
      );
      return RouteInfo(
        geometry: geometry,
        distanceKm: distanceKm,
        durationMin: durationMin,
        instructions: instructions,
      );
    } catch (error, stack) {
      _lastError = 'مسیریابی آفلاین با دادهٔ این نقشه ممکن نیست.';
      await AbmDebugLog.addRouting('ERROR exception=$error\n$stack');
      return null;
    }
  }

  Future<List<RouteInfo>> calculateRoutes({
    required LatLng origin,
    required LatLng destination,
    bool offlineOnly = false,
    bool avoidUnpavedRoads = false,
    bool avoidTolls = false,
  }) async {
    final r = await calculateRoute(
      origin: origin,
      destination: destination,
      offlineOnly: offlineOnly,
      avoidUnpavedRoads: avoidUnpavedRoads,
      avoidTolls: avoidTolls,
    );
    return r == null ? const [] : [r];
  }

  List<RouteInstruction> _buildInstructions(
      routing_engine_lib.AbmRouteResult result, List<LatLng> geometry) {
    if (geometry.length < 2 || result.edges.isEmpty) {
      return [RouteInstruction(
        text: RoutingInstructionLocalizer.text(
            languageCode: languageCode(), type: 'depart', modifier: null,
            roadName: null, exit: null),
        distanceMeters: 0,
        location: geometry.first,
        type: 'depart',
      )];
    }

    final out = <RouteInstruction>[];
    final language = languageCode();
    double travelled = 0;
    out.add(RouteInstruction(
      text: RoutingInstructionLocalizer.text(
          languageCode: language, type: 'depart', modifier: null,
          roadName: result.edges.first.name.isEmpty ? null : result.edges.first.name,
          exit: null),
      distanceMeters: 0,
      location: geometry.first,
      type: 'depart',
    ));

    var i = 1;
    var previousDistanceAlreadyAdded = false;
    while (i < result.edges.length) {
      final prev = result.edges[i - 1];
      final cur = result.edges[i];

      // A roundabout is one maneuver, not a sequence of ordinary turns.
      // Consume the whole roundabout at once so the card can use the exact
      // branch geometry/exit metadata calculated from map.sqlite.
      if (cur.junction.trim().toLowerCase() == 'roundabout') {
        if (!previousDistanceAlreadyAdded) {
          travelled += _distance(prev.from, prev.to);
        }
        final begin = i;
        var end = i;
        while (end < result.edges.length &&
            result.edges[end].junction.trim().toLowerCase() == 'roundabout') {
          end++;
        }
        final rb = result.edges[begin];
        final exitNode = result.edges[end - 1].to;
        final roadName = end < result.edges.length && result.edges[end].name.isNotEmpty
            ? result.edges[end].name
            : null;
        out.add(RouteInstruction(
          text: RoutingInstructionLocalizer.text(
            languageCode: language,
            type: 'roundabout',
            modifier: null,
            roadName: roadName,
            exit: rb.roundaboutExitNumber,
          ),
          distanceMeters: travelled,
          location: LatLng(rb.from.lat, rb.from.lon),
          type: 'roundabout',
          exit: rb.roundaboutExitNumber,
          roundaboutExitCount: rb.roundaboutExitCount,
          roundaboutBranchAngles: [
            for (final branch in rb.roundaboutBranches) branch.angleDegrees,
          ],
          roundaboutEntranceAngles: rb.roundaboutEntranceAngles,
          roundaboutExitAngles: rb.roundaboutExitAngles,
          roundaboutActiveExitAngle: rb.roundaboutActiveExitAngle,
          maneuverEndLocation: LatLng(exitNode.lat, exitNode.lon),
        ));

        // Consume the distance of every roundabout edge exactly once.
        for (var k = begin; k < end; k++) {
          travelled += _distance(result.edges[k].from, result.edges[k].to);
        }
        i = end;
        previousDistanceAlreadyAdded = true;
        continue;
      }

      if (!previousDistanceAlreadyAdded) {
        travelled += _distance(prev.from, prev.to);
      }
      previousDistanceAlreadyAdded = false;
      final delta = _signedAngle(
        _bearing(cur.from, cur.to) - _bearing(prev.from, prev.to),
      );
      final junctionChanged = prev.wayId != cur.wayId ||
          prev.name != cur.name ||
          prev.roadClass != cur.roadClass;
      final modifier = _modifierForDelta(delta, junctionChanged: junctionChanged);
      if (junctionChanged || modifier != 'straight') {
        out.add(RouteInstruction(
          text: RoutingInstructionLocalizer.text(
            languageCode: language,
            type: 'turn',
            modifier: modifier,
            roadName: cur.name.isEmpty ? null : cur.name,
            exit: null,
          ),
          distanceMeters: travelled,
          location: LatLng(cur.from.lat, cur.from.lon),
          type: modifier == 'uturn' ? 'uturn' : 'turn',
          modifier: modifier,
        ));
      }
      i++;
    }

    // Add the final edge to the total route distance. The last roundabout edge
    // is already included by the roundabout block above; this loop deliberately
    // sums every edge once so the destination ETA remains consistent.
    var total = 0.0;
    for (final edge in result.edges) {
      total += _distance(edge.from, edge.to);
    }
    out.add(RouteInstruction(
      text: RoutingInstructionLocalizer.text(
          languageCode: language, type: 'arrive', modifier: null,
          roadName: null, exit: null),
      distanceMeters: total,
      location: geometry.last,
      type: 'arrive',
    ));
    return out;
  }

  String _modifierForDelta(double delta, {bool junctionChanged = false}) {
    final a = delta.abs();
    // A U-turn is a maneuver class of its own. Do not force it into
    // left/right: near 180° the sign is numerically unstable and was the
    // reason genuine U-turns were sometimes rendered as ordinary turns.
    // Reserve U-turn for a genuinely reversed heading. A 135° bend can be a
    // sharp ramp/underpass exit and must remain a turn rather than a U-turn.
    if (a >= 150) return 'uturn';
    if (a >= 55) return delta > 0 ? 'right' : 'left';
    // A junction that changes way/road but bends only a few degrees is still
    // an actual slight turn. The old 20° threshold made bridge ramps and
    // shallow main-street exits look like a straight-through maneuver.
    if (a >= (junctionChanged ? 4 : 7)) {
      return delta > 0 ? 'slight right' : 'slight left';
    }
    return 'straight';
  }
  double _bearing(routing_engine_lib.RoutePoint a, routing_engine_lib.RoutePoint b) {
    final lat1 = a.lat * math.pi / 180, lat2 = b.lat * math.pi / 180, dl = (b.lon - a.lon) * math.pi / 180;
    final y = math.sin(dl) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dl);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }
  double _signedAngle(double angle) { var a = angle % 360; if (a > 180) a -= 360; if (a < -180) a += 360; return a; }
  double _estimateDurationMinutes(routing_engine_lib.AbmRouteResult result) {
    double seconds = 0;
    for (final e in result.edges) {
      final meters = _distance(e.from, e.to);
      final speed = (e.speedKmh ?? switch (e.roadClass) {
        'motorway' => 110.0, 'trunk' => 90.0, 'primary' => 70.0,
        'secondary' => 60.0, 'tertiary' => 50.0, 'residential' => 30.0, _ => 35.0,
      }).clamp(5.0, 160.0);
      seconds += meters / (speed / 3.6);
    }
    return seconds / 60;
  }
  double _distance(routing_engine_lib.RoutePoint a, routing_engine_lib.RoutePoint b) {
    const r = 6371008.8;
    final p1 = a.lat * math.pi / 180, p2 = b.lat * math.pi / 180;
    final dp = (b.lat - a.lat) * math.pi / 180, dl = (b.lon - a.lon) * math.pi / 180;
    final h = math.sin(dp / 2) * math.sin(dp / 2) + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    return r * 2 * math.asin(math.sqrt(h.clamp(0.0, 1.0)));
  }
  double _distanceKm(List<routing_engine_lib.RoutePoint> points) {
    double m = 0;
    for (var i = 1; i < points.length; i++) m += _distance(points[i - 1], points[i]);
    return m / 1000;
  }
}
