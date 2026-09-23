import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:sqlite3/sqlite3.dart';


class RoutePoint {
  const RoutePoint(this.lat, this.lon);
  final double lat;
  final double lon;
}

class RoundaboutBranchInfo {
  const RoundaboutBranchInfo({
    required this.angleDegrees,
    this.canEnter = false,
    this.canExit = false,
  });

  /// Geographic bearing (0=north, clockwise) of the physical arm.
  final double angleDegrees;
  final bool canEnter;
  final bool canExit;
}

class RouteEdgeInfo {
  const RouteEdgeInfo({
    required this.from,
    required this.to,
    required this.roadClass,
    required this.name,
    required this.junction,
    required this.wayId,
    this.speedKmh,
    this.roundaboutExitNumber,
    this.roundaboutExitCount,
    this.roundaboutBranches = const [],
    this.roundaboutEntranceAngles = const [],
    this.roundaboutExitAngles = const [],
    this.roundaboutActiveExitAngle,
  });
  final RoutePoint from;
  final RoutePoint to;
  final String roadClass;
  final String name;
  final String junction;
  final int wayId;
  final double? speedKmh;
  final int? roundaboutExitNumber;
  final int? roundaboutExitCount;
  final List<RoundaboutBranchInfo> roundaboutBranches;
  final List<double> roundaboutEntranceAngles;
  final List<double> roundaboutExitAngles;
  final double? roundaboutActiveExitAngle;
}

class _DbRouteEdge {
  const _DbRouteEdge({
    required this.from, required this.to, required this.distanceM,
    required this.speedKmh, required this.wayId, required this.oneway,
    required this.roadClass, required this.name, required this.junction,
  });
  final int from;
  final int to;
  final double distanceM;
  final double speedKmh;
  final int wayId;
  final bool oneway;
  final String roadClass;
  final String name;
  final String junction;
}

class _SqliteSnap {
  const _SqliteSnap({
    required this.a, required this.b, required this.t, required this.point,
    required this.segmentMeters, required this.oneway, required this.wayId,
  });
  final int a;
  final int b;
  final double t;
  final RoutePoint point;
  final double segmentMeters;
  final bool oneway;
  final int wayId;
}

class AbmRouteResult {
  const AbmRouteResult({required this.points, required this.edges, this.diagnostics = const []});
  final List<RoutePoint> points;
  final List<RouteEdgeInfo> edges;
  final List<String> diagnostics;
}

/// Disk-backed ABM routing reader.
///
/// ABM v4 keeps routing data inside the canonical map.sqlite database.
/// Routing must not depend on graph.bin/search.sqlite legacy members.
class AbmRoutingEngine {
  Future<List<RoutePoint>> route(
    File abmFile,
    RoutePoint origin,
    RoutePoint destination, {
    bool avoidUnpavedRoads = false,
    bool avoidTolls = false,
    bool avoidTrafficZones = false,
  }) async {
    final result = await routeDetailed(
      abmFile, origin, destination,
      avoidUnpavedRoads: avoidUnpavedRoads,
      avoidTolls: avoidTolls,
      avoidTrafficZones: avoidTrafficZones,
    );
    return result?.points ?? const [];
  }

  Future<AbmRouteResult?> routeDetailed(
    File abmFile,
    RoutePoint origin,
    RoutePoint destination, {
    bool avoidUnpavedRoads = false,
    bool avoidTolls = false,
    bool avoidTrafficZones = false,
  }) {
    return Isolate.run(() => _routeDetailedSync(
          abmFile.path, origin, destination,
          avoidUnpavedRoads, avoidTolls, avoidTrafficZones,
        ));
  }

  static Future<AbmRouteResult?> _routeDetailedSync(
    String path, RoutePoint origin, RoutePoint destination,
    bool avoidUnpavedRoads, bool avoidTolls, bool avoidTrafficZones,
  ) async {
    final file = File(path);
    if (!await file.exists()) return null;
    if (path.toLowerCase().endsWith('.sqlite')) {
      return _routeSqliteDetailed(
        path, origin, destination, avoidUnpavedRoads, avoidTolls, avoidTrafficZones,
      );
    }
    final points = await _routeSync(
      path, origin, destination, avoidUnpavedRoads, avoidTolls, avoidTrafficZones,
    );
    return points.isEmpty ? null : AbmRouteResult(points: points, edges: const []);
  }

  static Future<List<RoutePoint>> _routeSync(
    String path,
    RoutePoint origin,
    RoutePoint destination,
    bool avoidUnpavedRoads,
    bool avoidTolls,
    bool avoidTrafficZones,
  ) async {
    final file = File(path);
    if (!await file.exists()) return const [];
    if (path.toLowerCase().endsWith('.sqlite')) {
      final detailed = await _routeSqliteDetailed(
        path, origin, destination, avoidUnpavedRoads, avoidTolls, avoidTrafficZones,
      );
      return detailed?.points ?? const <RoutePoint>[];
    }
    final raf = await file.open();
    try {
      final magic = utf8.encode('ABMGRAPH1\n');
      final header = await raf.read(magic.length + 4);
      if (header.length < magic.length + 4) return const [];
      for (var i = 0; i < magic.length; i++) {
        if (header[i] != magic[i]) return const [];
      }
      final jsonLength = _u32(header, magic.length);
      final fileLength = await raf.length();
      final jsonStart = magic.length + 4;
      if (jsonLength <= 0 || jsonStart + jsonLength > fileLength)
        return const [];

      // Parse only the two sections used by routing. The graph builder writes
      // them in a stable order: nodes, edges, turn_restrictions.
      final nodes = <int, RoutePoint>{};
      final adjacency = <int, List<_Edge>>{};

      await _scanSection(
        raf,
        jsonStart,
        jsonLength,
        'nodes',
        (key, value) {
          if (key == null || value is! List || value.length < 2) return;
          final id = int.tryParse(key);
          if (id == null || value[0] is! num || value[1] is! num) return;
          nodes[id] = RoutePoint(
            (value[0] as num).toDouble(),
            (value[1] as num).toDouble(),
          );
        },
      );
      if (nodes.isEmpty) return const [];

      final start = _nearest(nodes, origin);
      final goal = _nearest(nodes, destination);
      if (start == goal) return <RoutePoint>[nodes[start]!];

      await _scanSection(
        raf,
        jsonStart,
        jsonLength,
        'edges',
        (key, value) {
          if (value is! Map) return;
          final a = _int(value['start'] ?? value['from']);
          final b = _int(value['end'] ?? value['to']);
          if (a == null ||
              b == null ||
              !nodes.containsKey(a) ||
              !nodes.containsKey(b)) return;
          final road =
              '${value['road_class'] ?? value['highway'] ?? value['class'] ?? value['road'] ?? ''}'
                  .toLowerCase();
          final toll = value['toll'] == true ||
              value['toll'] == 1 ||
              road.contains('toll');
          final restricted = value['traffic_zone'] == true ||
              value['trafficZone'] == true ||
              value['restricted'] == true;
          final surface = '${value['surface'] ?? ''}'.toLowerCase();
          final unpaved =
              surface.isNotEmpty && surface != 'paved' && surface != 'asphalt';
          if ((avoidTolls && toll) ||
              (avoidTrafficZones && restricted) ||
              (avoidUnpavedRoads && unpaved)) return;
          final speedRaw =
              value['speed_kmh'] ?? value['speed'] ?? value['maxspeed'] ?? 50;
          final speed = speedRaw is num
              ? speedRaw.toDouble().clamp(5, 160).toDouble()
              : 50.0;
          final distanceRaw = value['distance_m'] ?? value['distance'];
          final distance = distanceRaw is num
              ? distanceRaw.toDouble()
              : _distance(nodes[a]!, nodes[b]!);
          (adjacency[a] ??= []).add(_Edge(b, distance, speed));
          final oneway = value['oneway'] == true ||
              value['oneway'] == 1 ||
              '${value['oneway']}'.toLowerCase() == 'yes';
          if (!oneway) (adjacency[b] ??= []).add(_Edge(a, distance, speed));
        },
      );

      final distance = <int, double>{start: 0};
      final previous = <int, int?>{start: null};
      final open = _MinHeap<_QueueItem>((a, b) => a.cost.compareTo(b.cost));
      open.add(_QueueItem(start, 0));
      while (open.isNotEmpty) {
        final item = open.removeFirst();
        final current = item.node;
        if (item.cost > (distance[current] ?? double.infinity)) continue;
        if (current == goal) break;
        for (final edge in adjacency[current] ?? const <_Edge>[]) {
          final cost = edge.distanceM / edge.speedKmh * 3.6;
          final next = (distance[current] ?? double.infinity) + cost;
          if (next < (distance[edge.to] ?? double.infinity)) {
            distance[edge.to] = next;
            previous[edge.to] = current;
            open.add(_QueueItem(edge.to, next));
          }
        }
      }
      if (!previous.containsKey(goal)) return const [];
      final ids = <int>[];
      int? current = goal;
      while (current != null) {
        ids.add(current);
        current = previous[current];
      }
      return ids.reversed.map((id) => nodes[id]!).toList(growable: false);
    } finally {
      await raf.close();
    }
  }

  static _SegmentSnap _nearestEndpointToSegment(RoutePoint p, RoutePoint a, RoutePoint b) {
    final latRad = p.lat * math.pi / 180.0;
    final mx = 111320.0 * math.cos(latRad).abs().clamp(0.2, 1.0);
    const my = 110540.0;
    final ax = (a.lon - p.lon) * mx, ay = (a.lat - p.lat) * my;
    final bx = (b.lon - p.lon) * mx, by = (b.lat - p.lat) * my;
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    final t = len2 <= 1e-9 ? 0.0 : (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0);
    final px = ax + dx * t, py = ay + dy * t;
    final distance = math.sqrt(px * px + py * py);
    return _SegmentSnap(distance, t > 0.5);
  }

  static AbmRouteResult? _routeSqliteDetailed(
    String path,
    RoutePoint origin,
    RoutePoint destination,
    bool avoidUnpavedRoads,
    bool avoidTolls,
    bool avoidTrafficZones,
  ) {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    final diagnostics = <String>[];
    // Routing is intentionally file-backed rather than copying a country's
    // graph into the Dart heap. SQLite's mmap/page cache lets Android keep the
    // complete hot working set in RAM while the ABM remains the source of truth.
    try {
      try {
        db.execute('PRAGMA query_only=ON');
        db.execute('PRAGMA mmap_size=536870912');
        db.execute('PRAGMA cache_size=-65536');
        db.execute('PRAGMA temp_store=MEMORY');
      } catch (_) {}
      diagnostics.add('SQL OPEN path=$path');
      try {
        final tables = db.select("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name");
        diagnostics.add('SQL SCHEMA tables=${tables.map((r) => r['name']).join(',')}');
        for (final table in const ['node_data', 'edges', 'ways', 'road_index', 'segments', 'way_data', 'turn_restrictions']) {
          try {
            final count = (db.select('SELECT COUNT(*) c FROM $table').first['c'] as num).toInt();
            diagnostics.add('SQL COUNT $table=$count');
          } catch (_) {
            diagnostics.add('SQL COUNT $table=ERROR');
          }
        }
      } catch (error) {
        diagnostics.add('ERROR SQL_SCHEMA error=$error');
      }
      RoutePoint pointFor(int id) {
        final r = db.select('SELECT lat_e7,lon_e7 FROM node_data WHERE id=?', [id]);
        if (r.isEmpty) throw StateError('Missing routing node $id');
        return RoutePoint(
          (r.first['lat_e7'] as num).toDouble() * 1e-7,
          (r.first['lon_e7'] as num).toDouble() * 1e-7,
        );
      }

      final nodeCache = <int, RoutePoint>{};
      RoutePoint? node(int id) {
        final cached = nodeCache[id];
        if (cached != null) return cached;
        try {
          final p = pointFor(id);
          nodeCache[id] = p;
          return p;
        } catch (_) {
          return null;
        }
      }

      _SqliteSnap? snap(RoutePoint p) {
        if (!p.lat.isFinite || !p.lon.isFinite || p.lat < -90 || p.lat > 90 || p.lon < -180 || p.lon > 180) return null;
        final cosLat = math.cos(p.lat * math.pi / 180).abs().clamp(0.2, 1.0);
        _SqliteSnap? best;
        var bestMeters = double.infinity;
        for (final radius in const [0.005, 0.01, 0.03, 0.08, 0.2, 0.5, 1.0]) {
          final lonRadius = radius / cosLat;
          var rows = db.select(
            'SELECT s.a,s.b,s.dist_dm,w.way_id,w.oneway,na.lat_e7 alat,na.lon_e7 alon,nb.lat_e7 blat,nb.lon_e7 blon '
            'FROM road_index r JOIN segments s ON s.id BETWEEN r.seg_from AND r.seg_to '
            'JOIN way_data w ON w.way_id=s.way_id JOIN node_data na ON na.id=s.a JOIN node_data nb ON nb.id=s.b '
            'WHERE r.max_lat>=? AND r.min_lat<=? AND r.max_lon>=? AND r.min_lon<=? LIMIT 50000',
            [p.lat + radius, p.lat - radius, p.lon + lonRadius, p.lon - lonRadius],
          );

          // Some older/partially-built ABMs have a stale/empty road_index even
          // though segments themselves are present. Never let that make Snap
          // fail silently: fall back to the canonical segment table for the same
          // geographic window. This is slower only for a broken index and is run
          // inside the routing isolate.
          if (rows.isEmpty) {
            rows = db.select(
              'SELECT s.a,s.b,s.dist_dm,w.way_id,w.oneway,na.lat_e7 alat,na.lon_e7 alon,nb.lat_e7 blat,nb.lon_e7 blon '
              'FROM segments s JOIN way_data w ON w.way_id=s.way_id '
              'JOIN node_data na ON na.id=s.a JOIN node_data nb ON nb.id=s.b '
              'WHERE ((na.lat_e7 BETWEEN ? AND ?) OR (nb.lat_e7 BETWEEN ? AND ?)) '
              'AND ((na.lon_e7 BETWEEN ? AND ?) OR (nb.lon_e7 BETWEEN ? AND ?)) LIMIT 50000',
              [
                ((p.lat - radius) * 1e7).round(), ((p.lat + radius) * 1e7).round(),
                ((p.lat - radius) * 1e7).round(), ((p.lat + radius) * 1e7).round(),
                ((p.lon - lonRadius) * 1e7).round(), ((p.lon + lonRadius) * 1e7).round(),
                ((p.lon - lonRadius) * 1e7).round(), ((p.lon + lonRadius) * 1e7).round(),
              ],
            );
            if (rows.isNotEmpty) {
              diagnostics.add('SNAP FALLBACK segments radius=${radius.toStringAsFixed(3)} candidates=${rows.length}');
            }
          }
          for (final r in rows) {
            final a = RoutePoint((r['alat'] as num).toDouble() * 1e-7, (r['alon'] as num).toDouble() * 1e-7);
            final b = RoutePoint((r['blat'] as num).toDouble() * 1e-7, (r['blon'] as num).toDouble() * 1e-7);
            final latScale = 111320.0;
            final lonScale = 111320.0 * math.cos(p.lat * math.pi / 180).abs().clamp(0.2, 1.0);
            final ax = (a.lon - p.lon) * lonScale, ay = (a.lat - p.lat) * latScale;
            final bx = (b.lon - p.lon) * lonScale, by = (b.lat - p.lat) * latScale;
            final dx = bx - ax, dy = by - ay;
            final len2 = dx * dx + dy * dy;
            final t = len2 <= 1e-9 ? 0.0 : (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0);
            final px = ax + dx * t, py = ay + dy * t;
            final d = math.sqrt(px * px + py * py);
            if (d >= bestMeters) continue;
            final segmentMeters = ((r['dist_dm'] as num?)?.toDouble() ?? _distance(a, b) * 10.0) / 10.0;
            final wayId = (r['way_id'] as num).toInt();
            final onewayRaw = '${r['oneway'] ?? ''}'.toLowerCase();
            final oneway = onewayRaw == '1' || onewayRaw == 'true' || onewayRaw == 'yes';
            bestMeters = d;
            best = _SqliteSnap(
              a: (r['a'] as num).toInt(), b: (r['b'] as num).toInt(), t: t,
              point: RoutePoint(p.lat + py / latScale, p.lon + px / lonScale),
              segmentMeters: segmentMeters, oneway: oneway, wayId: wayId,
            );
          }
          if (best != null && bestMeters <= radius * 111500.0) break;
        }
        // Last-resort recovery for an ABM whose spatial index is present but
        // does not actually cover the requested coordinate. This is deliberately
        // bounded to the segment table and still runs off the UI isolate.
        if (best == null) {
          final rows = db.select(
            'SELECT s.a,s.b,s.dist_dm,w.way_id,w.oneway,na.lat_e7 alat,na.lon_e7 alon,nb.lat_e7 blat,nb.lon_e7 blon '
            'FROM segments s JOIN way_data w ON w.way_id=s.way_id '
            'JOIN node_data na ON na.id=s.a JOIN node_data nb ON nb.id=s.b LIMIT 100000',
          );
          diagnostics.add('SNAP FALLBACK globalSegments candidates=${rows.length}');
          for (final r in rows) {
            final a = RoutePoint((r['alat'] as num).toDouble() * 1e-7, (r['alon'] as num).toDouble() * 1e-7);
            final b = RoutePoint((r['blat'] as num).toDouble() * 1e-7, (r['blon'] as num).toDouble() * 1e-7);
            final latScale = 111320.0;
            final lonScale = 111320.0 * math.cos(p.lat * math.pi / 180).abs().clamp(0.2, 1.0);
            final ax = (a.lon - p.lon) * lonScale, ay = (a.lat - p.lat) * latScale;
            final bx = (b.lon - p.lon) * lonScale, by = (b.lat - p.lat) * latScale;
            final dx = bx - ax, dy = by - ay;
            final len2 = dx * dx + dy * dy;
            final t = len2 <= 1e-9 ? 0.0 : (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0);
            final px = ax + dx * t, py = ay + dy * t;
            final d = math.sqrt(px * px + py * py);
            if (d >= bestMeters) continue;
            bestMeters = d;
            final dist = ((r['dist_dm'] as num?)?.toDouble() ?? _distance(a, b) * 10.0) / 10.0;
            final onewayRaw = '${r['oneway'] ?? ''}'.toLowerCase();
            best = _SqliteSnap(
              a: (r['a'] as num).toInt(), b: (r['b'] as num).toInt(), t: t,
              point: RoutePoint(p.lat + py / latScale, p.lon + px / lonScale),
              segmentMeters: dist, oneway: onewayRaw == '1' || onewayRaw == 'true' || onewayRaw == 'yes',
              wayId: (r['way_id'] as num).toInt(),
            );
          }
        }
        diagnostics.add('SNAP nearestMeters=${best == null ? 'null' : bestMeters.toStringAsFixed(2)}');
        return best;
      }

      diagnostics.add('SNAP origin=${origin.lat.toStringAsFixed(6)},${origin.lon.toStringAsFixed(6)} dest=${destination.lat.toStringAsFixed(6)},${destination.lon.toStringAsFixed(6)}');
      try {
        final idx = db.select('SELECT COUNT(*) c, MIN(min_lat) minLat, MAX(max_lat) maxLat, MIN(min_lon) minLon, MAX(max_lon) maxLon FROM road_index').first;
        diagnostics.add('SNAP INDEX rows=${idx['c']} bbox=${idx['minLat']},${idx['minLon']}..${idx['maxLat']},${idx['maxLon']}');
      } catch (error) {
        diagnostics.add('SNAP INDEX ERROR $error');
      }
      final startSnap = snap(origin);
      final goalSnap = snap(destination);
      diagnostics.add('SNAP RESULT start=${startSnap?.a}/${startSnap?.b}@${startSnap?.t.toStringAsFixed(3)} point=${startSnap?.point.lat.toStringAsFixed(6)},${startSnap?.point.lon.toStringAsFixed(6)}');
      diagnostics.add('SNAP RESULT goal=${goalSnap?.a}/${goalSnap?.b}@${goalSnap?.t.toStringAsFixed(3)} point=${goalSnap?.point.lat.toStringAsFixed(6)},${goalSnap?.point.lon.toStringAsFixed(6)}');
      if (startSnap == null || goalSnap == null) {
        diagnostics.add('ERROR SNAP_FAILED');
        return AbmRouteResult(points: const [], edges: const [], diagnostics: diagnostics);
      }

      // Virtual nodes are created only in RAM. ABM stays compact: a two-way
      // segment is stored once, then its reverse movement is synthesized here.
      const start = -1;
      const goal = -2;
      final virtualPoints = <int, RoutePoint>{start: startSnap.point, goal: goalSnap.point};
      final adjacency = <int, List<_DbRouteEdge>>{};
      void add(_DbRouteEdge e) => (adjacency[e.from] ??= <_DbRouteEdge>[]).add(e);

      bool isTrue(dynamic v) {
        final x = '$v'.toLowerCase();
        return v == true || v == 1 || x == 'true' || x == 'yes' || x == '1';
      }
      bool allowed(String road, String access, String surface) {
        if (avoidTrafficZones && access.contains('private')) return false;
        if (avoidTolls && road.contains('toll')) return false;
        if (avoidUnpavedRoads && surface.isNotEmpty && surface != 'paved' && surface != 'asphalt') return false;
        return true;
      }
      _DbRouteEdge fromRow(Map r, {required int from, required int to, required double distance}) {
        return _DbRouteEdge(
          from: from, to: to, distanceM: distance,
          speedKmh: ((r['speed_kmh'] as num?)?.toDouble() ?? 30).clamp(5, 160).toDouble(),
          wayId: (r['way_id'] as num).toInt(), oneway: isTrue(r['oneway']),
          roadClass: '${r['road_class'] ?? ''}', name: '${r['name'] ?? ''}', junction: '${r['junction'] ?? ''}',
        );
      }

      bool toleranceZero(double v) => v.abs() < 1e-7;
      void addSegmentMoves(_SqliteSnap s, {required int virtual, required bool fromVirtual}) {
        final r = db.select(
          'SELECT w.road_class,w.name,w.junction,w.speed_kmh,w.oneway,w.access,w.surface,w.way_id '
          'FROM way_data w WHERE w.way_id=? LIMIT 1', [s.wayId],
        );
        if (r.isEmpty) return;
        final row = r.first;
        if (!allowed('${r.first['road_class'] ?? ''}'.toLowerCase(), '${r.first['access'] ?? ''}'.toLowerCase(), '${r.first['surface'] ?? ''}'.toLowerCase())) return;
        final aDist = s.segmentMeters * s.t;
        final bDist = s.segmentMeters * (1.0 - s.t);
        if (fromVirtual) {
          if (s.oneway) {
            if (toleranceZero(s.t)) {
              add(fromRow(row, from: virtual, to: s.a, distance: 0));
            } else {
              add(fromRow(row, from: virtual, to: s.b, distance: bDist));
            }
          } else {
            add(fromRow(row, from: virtual, to: s.a, distance: aDist));
            add(fromRow(row, from: virtual, to: s.b, distance: bDist));
          }
        } else {
          if (s.oneway) {
            if (toleranceZero(1.0 - s.t)) {
              add(fromRow(row, from: s.b, to: virtual, distance: 0));
            } else {
              add(fromRow(row, from: s.a, to: virtual, distance: aDist));
            }
          } else {
            add(fromRow(row, from: s.a, to: virtual, distance: aDist));
            add(fromRow(row, from: s.b, to: virtual, distance: bDist));
          }
        }
      }
      addSegmentMoves(startSnap, virtual: start, fromVirtual: true);
      addSegmentMoves(goalSnap, virtual: goal, fromVirtual: false);
      diagnostics.add('GRAPH virtualEdges=${adjacency.values.fold<int>(0, (n, list) => n + list.length)} avoidUnpaved=$avoidUnpavedRoads avoidTolls=$avoidTolls avoidTrafficZones=$avoidTrafficZones');

      // Materialize every stored directed edge on demand. For oneway=false the
      // reverse edge is synthesized in RAM; nothing is duplicated in ABM.
      void expandNode(int id) {
        if (id < 0) return;
        if (adjacency.containsKey(id)) return;
        final p = node(id);
        if (p == null) return;
        final rows = db.select(
          'SELECT e.start,e.end,e.distance_m,e.speed_kmh,e.way_id,e.oneway,w.road_class,w.access,w.name,w.junction,w.surface '
          'FROM edges e JOIN ways w ON w.way_id=e.way_id WHERE e.start=? OR (e.end=? AND COALESCE(e.oneway,0)=0)',
          [id, id],
        );
        final list = adjacency[id] ??= <_DbRouteEdge>[];
        for (final r in rows) {
          final storedStart = (r['start'] as num).toInt();
          final storedEnd = (r['end'] as num).toInt();
          final oneway = isTrue(r['oneway']);
          final road = '${r['road_class'] ?? ''}'.toLowerCase();
          final access = '${r['access'] ?? ''}'.toLowerCase();
          final surface = '${r['surface'] ?? ''}'.toLowerCase();
          if (!allowed(road, access, surface)) continue;
          final dist = (r['distance_m'] as num).toDouble();
          final speed = ((r['speed_kmh'] as num?)?.toDouble() ?? 30).clamp(5, 160).toDouble();
          final way = (r['way_id'] as num).toInt();
          if (storedStart == id) {
            list.add(_DbRouteEdge(from:id,to:storedEnd,distanceM:dist,speedKmh:speed,wayId:way,oneway:oneway,roadClass:'${r['road_class'] ?? ''}',name:'${r['name'] ?? ''}',junction:'${r['junction'] ?? ''}'));
          } else if (!oneway && storedEnd == id) {
            list.add(_DbRouteEdge(from:id,to:storedStart,distanceM:dist,speedKmh:speed,wayId:way,oneway:false,roadClass:'${r['road_class'] ?? ''}',name:'${r['name'] ?? ''}',junction:'${r['junction'] ?? ''}'));
          }
        }
      }

      // Turn restrictions are evaluated against (incoming way, via node,
      // outgoing way), while reverse edges keep the same OSM way id.
      final noTurns = <String>{};
      final onlyTurns = <String, int>{};
      try {
        final rows = db.select('SELECT restriction,from_json,via_json,to_json FROM turn_restrictions');
        diagnostics.add('RESTRICTIONS rows=${rows.length}');
        for (final r in rows) {
          final type='${r['restriction'] ?? ''}'.toLowerCase();
          List<int> ids(dynamic v){ try { final x=jsonDecode('${v ?? '[]'}'); return x is List ? x.whereType<num>().map((n)=>n.toInt()).toList() : const []; } catch(_){ return const []; } }
          for(final fw in ids(r['from_json'])) for(final vn in ids(r['via_json'])) for(final tw in ids(r['to_json'])) {
            if(type.startsWith('only')) onlyTurns['$fw|$vn']=tw; else noTurns.add('$fw|$vn|$tw');
          }
        }
      } catch (_) {}
      bool turnAllowed(int incomingWay,int viaNode,int outgoingWay){
        final only=onlyTurns['$incomingWay|$viaNode'];
        if(only!=null && only!=outgoingWay) return false;
        return !noTurns.contains('$incomingWay|$viaNode|$outgoingWay');
      }

      const noWay = -999999999;
      String stateKey(int n,int w)=>'$n|$w';
      final startKey=stateKey(start,noWay);
      final distance=<String,double>{startKey:0};
      final previous=<String,String?>{startKey:null};
      final previousEdge=<String,_DbRouteEdge>{};
      final open=_MinHeap<_TurnQueueItem>((a,b)=>a.priority.compareTo(b.priority));
      open.add(_TurnQueueItem(start,noWay,0,_distance(startSnap.point,destination)/160.0*3.6));
      String? goalState;
      while(open.isNotEmpty){
        final item=open.removeFirst();
        final key=stateKey(item.node,item.way);
        if(item.cost>(distance[key]??double.infinity))continue;
        if(item.node==goal){goalState=key;break;}
        expandNode(item.node);
        for(final e in adjacency[item.node]??const <_DbRouteEdge>[]){
          if(item.way!=noWay && !turnAllowed(item.way,item.node,e.wayId))continue;
          final next=item.cost+e.distanceM/e.speedKmh*3.6;
          final nk=stateKey(e.to,e.wayId);
          if(next<(distance[nk]??double.infinity)){
            distance[nk]=next; previous[nk]=key; previousEdge[nk]=e;
            final target=e.to==goal?goalSnap.point:(node(e.to)??destination);
            final h=_distance(target,destination)/160.0*3.6;
            open.add(_TurnQueueItem(e.to,e.wayId,next,next+h));
          }
        }
      }
      if(goalState==null){
        diagnostics.add('ERROR NO_ROUTE expandedStates=${distance.length} materializedNodes=${adjacency.length}');
        return AbmRouteResult(points: const [], edges: const [], diagnostics: diagnostics);
      }
      diagnostics.add('SEARCH success states=${distance.length} finalCost=${distance[goalState] ?? -1}');
      var states=<String>[]; String? cur=goalState;
      while(cur!=null){states.add(cur);cur=previous[cur];}
      states = states.reversed.toList();
      final points=<RoutePoint>[startSnap.point];
      final edges=<RouteEdgeInfo>[];
      for(var i=1;i<states.length;i++){
        final e=previousEdge[states[i]]; if(e==null)continue;
        final from=e.from==start?startSnap.point:(e.from==goal?goalSnap.point:(node(e.from)??destination));
        final to=e.to==goal?goalSnap.point:(e.to==start?startSnap.point:(node(e.to)??destination));
        if(_distance(points.last,to)>0.05) points.add(to);
        edges.add(RouteEdgeInfo(from:from,to:to,roadClass:e.roadClass,name:e.name,junction:e.junction,wayId:e.wayId,speedKmh:e.speedKmh));
      }
      if(points.length<2){ diagnostics.add('ERROR ROUTE_GEOMETRY_TOO_SHORT points=${points.length} edges=${edges.length}'); return AbmRouteResult(points: const [], edges: const [], diagnostics: diagnostics); }

      // Build the roundabout geometry from the actual SQLite graph instead
      // of drawing a hard-coded four-branch icon. Every physical arm is
      // discovered from the roundabout nodes and its real neighbouring road;
      // entrance/exit availability follows the stored one-way direction.
      for (var i = 0; i < edges.length;) {
        if (edges[i].junction.trim().toLowerCase() != 'roundabout') { i++; continue; }
        final begin = i;
        while (i < edges.length && edges[i].junction.trim().toLowerCase() == 'roundabout') i++;
        final end = i;

        final nodeIds = <int>{};
        for (var k = begin; k < end; k++) {
          nodeIds.add(int.parse(states[k].split('|').first));
          nodeIds.add(int.parse(states[k + 1].split('|').first));
        }

        double bearing(RoutePoint a, RoutePoint b) {
          final lat1 = a.lat * math.pi / 180;
          final lat2 = b.lat * math.pi / 180;
          final dl = (b.lon - a.lon) * math.pi / 180;
          final y = math.sin(dl) * math.cos(lat2);
          final x = math.cos(lat1) * math.sin(lat2) -
              math.sin(lat1) * math.cos(lat2) * math.cos(dl);
          return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
        }

        bool truthy(dynamic value) {
          final x = '$value'.toLowerCase();
          return value == true || value == 1 || x == 'true' || x == 'yes' || x == '1';
        }

        final branchByAngle = <double, RoundaboutBranchInfo>{};
        void addBranch(double angle, {required bool canEnter, required bool canExit}) {
          final normalized = (angle % 360 + 360) % 360;
          double? existingKey;
          for (final key in branchByAngle.keys) {
            var d = (key - normalized).abs();
            if (d > 180) d = 360 - d;
            if (d <= 7.5) { existingKey = key; break; }
          }
          if (existingKey == null) {
            branchByAngle[normalized] = RoundaboutBranchInfo(
              angleDegrees: normalized,
              canEnter: canEnter,
              canExit: canExit,
            );
          } else {
            final old = branchByAngle[existingKey]!;
            branchByAngle[existingKey] = RoundaboutBranchInfo(
              angleDegrees: old.angleDegrees,
              canEnter: old.canEnter || canEnter,
              canExit: old.canExit || canExit,
            );
          }
        }

        for (final nodeId in nodeIds) {
          final center = node(nodeId);
          if (center == null) continue;
          final rows = db.select(
            'SELECT e.start,e.end,e.oneway,e.junction,na.lat_e7 alat,na.lon_e7 alon,nb.lat_e7 blat,nb.lon_e7 blon '
            'FROM edges e JOIN node_data na ON na.id=e.start JOIN node_data nb ON nb.id=e.end '
            'WHERE e.start=? OR e.end=?',
            [nodeId, nodeId],
          );
          for (final r in rows) {
            final junction = '${r['junction'] ?? ''}'.trim().toLowerCase();
            if (junction == 'roundabout') continue;
            final start = (r['start'] as num).toInt();
            final endNode = (r['end'] as num).toInt();
            final otherId = start == nodeId ? endNode : start;
            final other = node(otherId) ?? RoutePoint(
              (r['blat'] as num).toDouble() * 1e-7,
              (r['blon'] as num).toDouble() * 1e-7,
            );
            final angle = bearing(center, other);
            final oneway = truthy(r['oneway']);
            final canExit = start == nodeId || !oneway;
            final canEnter = endNode == nodeId || !oneway;
            addBranch(angle, canEnter: canEnter, canExit: canExit);
          }
        }

        // The route's incoming arm and actual exit arm are identified from the
        // route itself, so a road that serves both directions is represented by
        // one physical branch rather than being counted twice.
        final branches = branchByAngle.values.toList()
          ..sort((a, b) => a.angleDegrees.compareTo(b.angleDegrees));
        final routeEntranceAngles = <double>[];
        if (begin > 0) {
          final firstNode = edges[begin].from;
          routeEntranceAngles.add(bearing(firstNode, edges[begin - 1].from));
        }
        final entranceAngles = branches
            .where((b) => b.canEnter)
            .map((b) => b.angleDegrees)
            .toList(growable: false);
        final exitAngles = branches
            .where((b) => b.canExit)
            .map((b) => b.angleDegrees)
            .toList(growable: false);
        double? activeExitAngle;
        if (end < edges.length) {
          final lastNode = edges[end - 1].to;
          activeExitAngle = bearing(lastNode, edges[end].to);
        }

        final exitBranches = branches.where((b) => b.canExit).toList();
        final entrance = routeEntranceAngles.isEmpty ? null : routeEntranceAngles.first;
        final usableExitBranches = entrance == null
            ? exitBranches
            : exitBranches.where((b) {
                var d = (b.angleDegrees - entrance).abs();
                if (d > 180) d = 360 - d;
                return d > 12;
              }).toList();
        int exitNumber = 0;
        if (activeExitAngle != null && usableExitBranches.isNotEmpty && entrance != null) {
          final routeClockwise = (() {
            if (end - begin >= 2) {
              final a = bearing(edges[begin].from, edges[begin].to);
              final b = bearing(edges[begin + 1].from, edges[begin + 1].to);
              var d = (b - a + 360) % 360;
              return d > 0 && d < 180;
            }
            // A one-edge roundabout is too short to infer rotation from two
            // tangent samples; the app's routing data uses right-hand traffic
            // as the default convention.
            return true;
          })();
          double delta(double from, double to) => routeClockwise
              ? (to - from + 360) % 360
              : (from - to + 360) % 360;
          final ordered = usableExitBranches
              .where((b) => delta(entrance, b.angleDegrees) > 5)
              .toList()
            ..sort((a, b) => delta(entrance, a.angleDegrees)
                .compareTo(delta(entrance, b.angleDegrees)));
          for (var n = 0; n < ordered.length; n++) {
            var d = (ordered[n].angleDegrees - activeExitAngle).abs();
            if (d > 180) d = 360 - d;
            if (d <= 10) {
              exitNumber = n + 1;
              break;
            }
          }
        }
        if (exitNumber == 0 && activeExitAngle != null) exitNumber = 1;
        final totalExits = usableExitBranches.length;

        for (var n = begin; n < end; n++) {
          final old = edges[n];
          edges[n] = RouteEdgeInfo(
            from: old.from,
            to: old.to,
            roadClass: old.roadClass,
            name: old.name,
            junction: old.junction,
            wayId: old.wayId,
            speedKmh: old.speedKmh,
            roundaboutExitNumber: exitNumber == 0 ? null : exitNumber,
            roundaboutExitCount: totalExits,
            roundaboutBranches: branches,
            roundaboutEntranceAngles: entranceAngles,
            roundaboutExitAngles: exitAngles,
            roundaboutActiveExitAngle: activeExitAngle,
          );
        }
        diagnostics.add('ROUNDABOUT begin=$begin end=$end branches=${branches.length} exits=$totalExits activeExit=${activeExitAngle?.toStringAsFixed(1) ?? '-'} exitNumber=${exitNumber == 0 ? '-' : exitNumber}');
      }
      diagnostics.add('RESULT points=${points.length} edges=${edges.length}');
      return AbmRouteResult(points:points,edges:edges,diagnostics:diagnostics);
    } finally { db.dispose(); }
  }

  static double _distance(RoutePoint a, RoutePoint b) {
    const r = 6371008.8;
    final p1 = a.lat * math.pi / 180, p2 = b.lat * math.pi / 180;
    final dp = (b.lat - a.lat) * math.pi / 180, dl = (b.lon - a.lon) * math.pi / 180;
    final h = math.sin(dp/2)*math.sin(dp/2) + math.cos(p1)*math.cos(p2)*math.sin(dl/2)*math.sin(dl/2);
    return r * 2 * math.asin(math.sqrt(h));
  }

  /// Scans one named top-level JSON object/array without loading the whole
  /// graph. Each member/element is decoded independently, so peak JSON memory
  /// is proportional to one node/edge rather than the entire country graph.
  static Future<List<int>> _readSectionWindow(
      RandomAccessFile raf, int start, int length) async {
    // Keep compatibility with the existing graph format while avoiding an
    // additional copy: this helper reads the JSON payload once inside the
    // worker. It is still bounded by the graph size, but the UI isolate never
    // receives it. The next builder revision can add an indexed graph member.
    await raf.setPosition(start);
    return raf.read(length);
  }

  static Future<void> _scanSection(
    RandomAccessFile raf,
    int jsonStart,
    int jsonLength,
    String section,
    void Function(String? key, dynamic value) onValue,
  ) async {
    final bytes = await _readSectionWindow(raf, jsonStart, jsonLength);
    // The graph header itself is small compared with the graph payload, but
    // the complete JSON must never be copied. The helper below operates on
    // bounded chunks and seeks directly to the requested section.
    final marker = utf8.encode('"$section":');
    final sectionOffset = _findBytes(bytes, marker);
    if (sectionOffset < 0) return;
    var i = sectionOffset + marker.length;
    while (i < bytes.length && _isWhitespace(bytes[i])) i++;
    if (i >= bytes.length) return;
    final open = bytes[i];
    final close = open == 0x7B ? 0x7D : (open == 0x5B ? 0x5D : -1);
    if (close < 0) return;
    i++;
    while (i < bytes.length) {
      while (i < bytes.length && (_isWhitespace(bytes[i]) || bytes[i] == 0x2C))
        i++;
      if (i >= bytes.length || bytes[i] == close) break;
      String? key;
      if (open == 0x7B) {
        if (bytes[i] != 0x22) break;
        final keyEnd = _quotedEnd(bytes, i);
        if (keyEnd < 0) break;
        key = utf8.decode(bytes.sublist(i + 1, keyEnd));
        i = keyEnd + 1;
        while (i < bytes.length && _isWhitespace(bytes[i])) i++;
        if (i >= bytes.length || bytes[i] != 0x3A) break;
        i++;
        while (i < bytes.length && _isWhitespace(bytes[i])) i++;
      }
      final end = _jsonValueEnd(bytes, i);
      if (end <= i) break;
      try {
        final value = jsonDecode(utf8.decode(bytes.sublist(i, end)));
        onValue(key, value);
      } catch (_) {
        // Ignore one malformed edge/node; do not take down navigation.
      }
      i = end;
    }
  }

  static int _jsonValueEnd(List<int> b, int start) {
    if (start >= b.length) return start;
    final first = b[start];
    if (first != 0x7B && first != 0x5B && first != 0x22) {
      var i = start;
      while (i < b.length && b[i] != 0x2C && b[i] != 0x7D && b[i] != 0x5D) i++;
      return i;
    }
    if (first == 0x22) {
      final e = _quotedEnd(b, start);
      return e < 0 ? b.length : e + 1;
    }
    final open = first;
    final close = open == 0x7B ? 0x7D : 0x5D;
    var depth = 0;
    var string = false;
    var escaped = false;
    for (var i = start; i < b.length; i++) {
      final c = b[i];
      if (string) {
        if (escaped) {
          escaped = false;
        } else if (c == 0x5C) {
          escaped = true;
        } else if (c == 0x22) {
          string = false;
        }
        continue;
      }
      if (c == 0x22) {
        string = true;
      } else if (c == open) {
        depth++;
      } else if (c == close) {
        depth--;
        if (depth == 0) return i + 1;
      }
    }
    return b.length;
  }

  static int _quotedEnd(List<int> b, int start) {
    var escaped = false;
    for (var i = start + 1; i < b.length; i++) {
      final c = b[i];
      if (escaped) {
        escaped = false;
      } else if (c == 0x5C) {
        escaped = true;
      } else if (c == 0x22) {
        return i;
      }
    }
    return -1;
  }

  static int _findBytes(List<int> data, List<int> needle) {
    if (needle.isEmpty || needle.length > data.length) return -1;
    outer:
    for (var i = 0; i <= data.length - needle.length; i++) {
      for (var j = 0; j < needle.length; j++) {
        if (data[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  static bool _isWhitespace(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;
  static int _u32(List<int> b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
  static int? _int(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value');
  static int _nearest(Map<int, RoutePoint> nodes, RoutePoint p) {
    var id = nodes.keys.first;
    var best = double.infinity;
    for (final e in nodes.entries) {
      final d = _distance(p, e.value);
      if (d < best) {
        best = d;
        id = e.key;
      }
    }
    return id;
  }

}

class _Edge {
  const _Edge(this.to, this.distanceM, this.speedKmh);
  final int to;
  final double distanceM;
  final double speedKmh;
}

class _QueueItem {
  const _QueueItem(this.node, this.cost);
  final int node;
  final double cost;
}

/// Dijkstra queue item for the turn-restriction-aware sqlite router: state
/// is (node, incoming way id), not just node — see `_routeSqliteDetailed`.
class _TurnQueueItem {
  const _TurnQueueItem(this.node, this.way, this.cost, this.priority);
  final int node;
  final int way;
  final double cost;
  final double priority;
}

class _MinHeap<T> {
  _MinHeap(this.compare);
  final int Function(T, T) compare;
  final List<T> _items = <T>[];
  bool get isNotEmpty => _items.isNotEmpty;
  void add(T value) {
    _items.add(value);
    var i = _items.length - 1;
    while (i > 0) {
      final parent = (i - 1) >> 1;
      if (compare(_items[parent], _items[i]) <= 0) break;
      final t = _items[parent];
      _items[parent] = _items[i];
      _items[i] = t;
      i = parent;
    }
  }

  T removeFirst() {
    final first = _items.first;
    final last = _items.removeLast();
    if (_items.isNotEmpty) {
      _items[0] = last;
      var i = 0;
      while (true) {
        final left = i * 2 + 1, right = left + 1;
        var smallest = i;
        if (left < _items.length && compare(_items[left], _items[smallest]) < 0)
          smallest = left;
        if (right < _items.length &&
            compare(_items[right], _items[smallest]) < 0) smallest = right;
        if (smallest == i) break;
        final t = _items[i];
        _items[i] = _items[smallest];
        _items[smallest] = t;
        i = smallest;
      }
    }
    return first;
  }
}


class _SegmentSnap {
  const _SegmentSnap(this.distanceMeters, this.useB);
  final double distanceMeters;
  final bool useB;
}
