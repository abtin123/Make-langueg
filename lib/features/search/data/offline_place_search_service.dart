import 'dart:isolate';
import 'dart:math' as math;

import 'package:sqlite3/sqlite3.dart';

import '../../../abtinmap/abm_map_service.dart';
import '../../../core/abm_debug_log.dart';
import '../../../core/geo/geo_types.dart';
import '../../offline_maps/data/vector_map_service.dart';
import 'place_search_service.dart';

/// Offline POI search adapter backed by the canonical ABM map.sqlite database.
class OfflinePlaceSearchService {
  OfflinePlaceSearchService(this._maps);
  final AbmMapService _maps;
  final VectorMapService _vectorMaps = VectorMapService();

  Future<List<PlaceSearchResult>> search(
    String query, {
    required String mapFileName,
    double? biasLat,
    double? biasLng,
    String? city,
    int limit = 12,
  }) async {
    final trimmed = query.trim();
    await AbmDebugLog.addPoi(
      'START query="$trimmed" map="$mapFileName" city=${city ?? '-'} limit=$limit '
      'bias=${biasLat?.toStringAsFixed(6)},${biasLng?.toStringAsFixed(6)}',
    );
    if (trimmed.length < 2) {
      await AbmDebugLog.addPoi('STOP query_too_short length=${trimmed.length}');
      return const [];
    }
    final container = await _maps.localFile(mapFileName);
    await AbmDebugLog.addPoi('MAP file=${container.path} exists=${await container.exists()}');
    if (!await container.exists()) {
      await AbmDebugLog.addPoi('ERROR map_file_missing');
      return const [];
    }
    final id = mapFileName.toLowerCase().endsWith('.abm')
        ? mapFileName.substring(0, mapFileName.length - 4)
        : mapFileName;
    try {
      await AbmDebugLog.addPoi('PREPARE begin id=$id size=${await container.length()}');
      final artifacts = await _vectorMaps.prepare(containerFile: container, id: id);
      await AbmDebugLog.addPoi(
        'PREPARE done sqlite=${artifacts.sqliteFile.path} sqliteBytes=${await artifacts.sqliteFile.length()} '
        'metadataKeys=${artifacts.metadata.keys.length}',
      );
      final raw = await Isolate.run(() => _searchSync(
            artifacts.sqliteFile.path,
            trimmed,
            biasLat,
            biasLng,
            limit,
          ));
      for (final line in (raw['trace'] as List).cast<String>()) {
        await AbmDebugLog.addPoi(line);
      }
      final rows = (raw['results'] as List).cast<Map>();
      final results = rows.map((r) => PlaceSearchResult(
            name: '${r['name']}',
            region: (r['region'] as String?)?.isEmpty == true ? null : r['region'] as String?,
            point: LatLng((r['lat'] as num).toDouble(), (r['lon'] as num).toDouble()),
            isOffline: true,
            distanceMeters: (r['distance'] as num?)?.toDouble(),
          )).toList(growable: false);
      await AbmDebugLog.addPoi('END success results=${results.length}');
      return results;
    } catch (error, stack) {
      await AbmDebugLog.addPoi('ERROR search_failed error=$error\n$stack');
      return const [];
    }
  }

  static Map<String, dynamic> _searchSync(
    String sqlitePath,
    String query,
    double? biasLat,
    double? biasLng,
    int limit,
  ) {
    final trace = <String>[];
    trace.add('SQL OPEN path=$sqlitePath');
    final db = sqlite3.open(sqlitePath, mode: OpenMode.readOnly);
    try {
      final objects = db.select(
        "SELECT name,type FROM sqlite_master WHERE type IN ('table','view') ORDER BY name",
      );
      trace.add('SQL SCHEMA objects=${objects.length} names=${objects.map((r) => r['name']).join(',')}');
      final normalized = query
          .replaceAll('ي', 'ی')
          .replaceAll('ى', 'ی')
          .replaceAll('ك', 'ک')
          .replaceAll('\u200c', ' ')
          .trim()
          .toLowerCase();
      trace.add('QUERY normalized="$normalized" ftsLimit=${(limit * 4).clamp(12, 64)}');
      final rows = db.select(
        'SELECT f.id,c.name category,n.name,n.name_fa,n.name_en,f.opening_hours,'
        '(s.min_lat+s.max_lat)/2 lat,(s.min_lon+s.max_lon)/2 lon '
        'FROM search_fts JOIN names n ON n.id=search_fts.rowid '
        'JOIN features f ON f.name_id=n.id LEFT JOIN categories c ON c.id=f.category_id '
        'LEFT JOIN spatial s ON s.id=f.id WHERE search_fts MATCH ? LIMIT ?',
        ['"$normalized"*', (limit * 4).clamp(12, 64)],
      );
      trace.add('SQL FTS rows=${rows.length}');
      final origin = biasLat == null || biasLng == null ? null : LatLng(biasLat, biasLng);
      final results = <Map<String, dynamic>>[];
      var skippedNoPoint = 0;
      for (final r in rows) {
        final lat = (r['lat'] as num?)?.toDouble();
        final lon = (r['lon'] as num?)?.toDouble();
        if (lat == null || lon == null) {
          skippedNoPoint++;
          continue;
        }
        final point = LatLng(lat, lon);
        results.add({
          'name': _firstText(r['name_fa'], r['name'], r['name_en']) ?? query,
          'region': '${r['category'] ?? ''}'.trim(),
          'lat': lat,
          'lon': lon,
          'distance': origin == null ? null : _distance(origin, point),
        });
      }
      results.sort((a, b) => ((a['distance'] as num?)?.toDouble() ?? double.infinity)
          .compareTo((b['distance'] as num?)?.toDouble() ?? double.infinity));
      final limited = results.take(limit).toList(growable: false);
      trace.add('RESULTS usable=${results.length} skippedNoPoint=$skippedNoPoint returned=${limited.length}');
      for (var i = 0; i < limited.length; i++) {
        final r = limited[i];
        trace.add('RESULT[$i] name="${r['name']}" category="${r['region']}" '
            'point=${(r['lat'] as num).toStringAsFixed(6)},${(r['lon'] as num).toStringAsFixed(6)} '
            'distanceM=${(r['distance'] as num?)?.toStringAsFixed(1) ?? '-'}');
      }
      return {'results': limited, 'trace': trace};
    } catch (error, stack) {
      trace.add('ERROR SQL_POI error=$error\n$stack');
      return {'results': const [], 'trace': trace};
    } finally {
      db.dispose();
    }
  }

  static String? _firstText(Object? a, Object? b, Object? c) {
    for (final value in [a, b, c]) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  static double _distance(LatLng a, LatLng b) {
    const r = 6371008.8;
    final p1 = a.latitude * 3.141592653589793 / 180;
    final p2 = b.latitude * 3.141592653589793 / 180;
    final dp = (b.latitude - a.latitude) * 3.141592653589793 / 180;
    final dl = (b.longitude - a.longitude) * 3.141592653589793 / 180;
    final h = math.sin(dp / 2) * math.sin(dp / 2) +
        math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    return r * 2 * math.asin(math.sqrt(h.clamp(0.0, 1.0)));
  }
}
