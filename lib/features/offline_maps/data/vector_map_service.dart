import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../../core/abm_debug_log.dart';


class VectorMapInstallException implements Exception {
  const VectorMapInstallException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AbmBBox {
  const AbmBBox(this.minLon, this.minLat, this.maxLon, this.maxLat);
  final double minLon;
  final double minLat;
  final double maxLon;
  final double maxLat;
}

class AbmVectorFeature {
  const AbmVectorFeature({
    required this.id,
    required this.layer,
    required this.geometry,
    required this.properties,
    required this.bbox,
    this.renderPriority = 0,
    this.minZoom = 0,
  });
  final int id;
  final String layer;
  final List<List<double>> geometry;
  final Map<String, dynamic> properties;
  final AbmBBox bbox;
  final int renderPriority;
  final double minZoom;

  Map<String, dynamic> toGeoJson() => {
        'type': 'Feature',
        'id': id,
        'geometry': {
          'type': geometry.length == 1 ? 'Point' : 'LineString',
          'coordinates': geometry.length == 1 ? geometry.first : geometry,
        },
        'properties': properties,
      };
}

class VectorMapArtifacts {
  const VectorMapArtifacts({required this.sqliteFile, required this.metadata});
  /// The canonical map database extracted from the ABM container.
  /// SQLite remains file-backed; the whole database is never copied into RAM.
  final File sqliteFile;
  final Map<String, dynamic> metadata;
}

class VectorMapService {
  /// SQLite is file-backed on purpose. mmap lets the OS keep hot pages in RAM
  /// without copying a 50–100+ MB country database into the Dart heap.
  static void configureReadOnly(sqlite.Database db) {
    try {
      db.execute('PRAGMA query_only=ON');
      db.execute('PRAGMA mmap_size=536870912');
      db.execute('PRAGMA cache_size=-65536');
      db.execute('PRAGMA temp_store=MEMORY');
    } catch (_) {}
  }
  final Map<String, Future<VectorMapArtifacts>> _inFlight = <String, Future<VectorMapArtifacts>>{};
  Future<Directory> dataDirectory(String id) async {
    final base = await getApplicationSupportDirectory();
    final d = Directory(p.join(base.path, 'AbtinMaps', 'maps', id.toUpperCase()));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<bool> isInstalled({required File containerFile}) async {
    try {
      return await containerFile.exists() && await containerFile.length() > 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> delete(String id) async {
    final d = await dataDirectory(id);
    if (await d.exists()) await d.delete(recursive: true);
  }

  Future<VectorMapArtifacts> prepare({
    required File containerFile,
    required String id,
    void Function(double)? onProgress,
  }) {
    final key = containerFile.path;
    final running = _inFlight[key];
    if (running != null) return running;
    final future = _prepareInternal(containerFile: containerFile, id: id, onProgress: onProgress);
    _inFlight[key] = future;
    return future.whenComplete(() => _inFlight.remove(key));
  }

  Future<VectorMapArtifacts> _prepareInternal({
    required File containerFile,
    required String id,
    void Function(double)? onProgress,
  }) async {
    if (!await isInstalled(containerFile: containerFile)) {
      throw const VectorMapInstallException('Map file is missing or empty.');
    }

    final data = await dataDirectory(id);
    final sqliteFile = File(p.join(data.path, 'map.sqlite'));
    final metadataFile = File(p.join(data.path, 'metadata.json'));
    final marker = File(p.join(data.path, '.abm-source'));
    final stat = await containerFile.stat();
    const extractionRevision = 'sqlite-only-v1';
    final sourceMarker = '$extractionRevision:${stat.size}:${stat.modified.millisecondsSinceEpoch}';

    final extractedReady = await sqliteFile.exists() &&
        await sqliteFile.length() > 0 &&
        await metadataFile.exists() &&
        await marker.exists() &&
        (await marker.readAsString()) == sourceMarker;

    if (!extractedReady) {
      final tmp = Directory(p.join(data.path, '.extract-${DateTime.now().microsecondsSinceEpoch}'));
      await tmp.create(recursive: true);
      try {
        // ABM is only a transport/container format. The renderer, search and
        // routing all read the canonical map.sqlite directly after this one
        // extraction. There is deliberately no MBTiles cache/rebuild stage.
        await AbmDebugLog.addMap('ABM EXTRACT id=$id sourceBytes=${stat.size}');
        await Isolate.run(() => _extractSqliteAndMetadata(containerFile.path, tmp.path));

        final extractedSqlite = File(p.join(tmp.path, 'map.sqlite'));
        _validateSqlite(extractedSqlite);
        final extractedMetadata = File(p.join(tmp.path, 'metadata.json'));
        if (!await extractedMetadata.exists() || await extractedMetadata.length() == 0) {
          throw const VectorMapInstallException('ABM metadata.json is missing or empty.');
        }

        await _replaceFile(extractedSqlite, sqliteFile);
        await _replaceFile(extractedMetadata, metadataFile);
        await marker.writeAsString(sourceMarker, flush: true);
      } catch (error) {
        if (await marker.exists()) {
          final value = await marker.readAsString();
          if (value == sourceMarker) await marker.delete();
        }
        rethrow;
      } finally {
        if (await tmp.exists()) await tmp.delete(recursive: true);
      }
    } else {
      // Existing extraction is reused; this is not a query cache and no
      // database rebuild/copy happens on map viewport refreshes.
      await AbmDebugLog.addMap(
        'ABM EXTRACTED HIT id=$id sqliteBytes=${await sqliteFile.length()} sourceBytes=${stat.size}',
      );
    }

    await AbmDebugLog.addMap(
      'SQLITE READY id=$id path=${sqliteFile.path} sqliteBytes=${await sqliteFile.length()}',
    );
    final metadata = jsonDecode(await metadataFile.readAsString()) as Map<String, dynamic>;
    onProgress?.call(1);
    return VectorMapArtifacts(sqliteFile: sqliteFile, metadata: metadata);
  }

  Future<File> sqliteFileFor({required File containerFile, required String id}) async =>
      (await prepare(containerFile: containerFile, id: id)).sqliteFile;

  static Future<void> _replaceFile(File source, File target) async {
    if (!await source.exists()) throw const VectorMapInstallException('ABM archive is missing a required member.');
    final temp = File('${target.path}.part');
    if (await temp.exists()) await temp.delete();
    await source.copy(temp.path);
    if (await target.exists()) await target.delete();
    await temp.rename(target.path);
  }

  static void _extractSqliteAndMetadata(String archivePath, String outputDir) {
    final input = InputFileStream(archivePath);
    final found = <String, int>{};
    try {
      final archive = ZipDecoder().decodeStream(input);
      const wanted = {'map.sqlite', 'metadata.json'};
      for (final entry in archive) {
        if (!entry.isFile) continue;
        final normalized = entry.name.replaceAll('\\', '/');
        final base = p.basename(normalized);
        if (!wanted.contains(base) || normalized.split('/').length > 2) continue;
        final output = OutputFileStream(p.join(outputDir, base));
        try {
          entry.writeContent(output);
        } finally {
          output.closeSync();
        }
        found[base] = entry.size;
      }
      for (final name in wanted) {
        final file = File(p.join(outputDir, name));
        if (!file.existsSync() || file.lengthSync() <= 0) {
          throw VectorMapInstallException('ABM extraction incomplete: missing $name');
        }
        final expected = found[name];
        if (expected != null && file.lengthSync() != expected) {
          throw VectorMapInstallException(
            'ABM extraction incomplete: $name expected=$expected actual=${file.lengthSync()}',
          );
        }
      }
    } finally {
      input.closeSync();
    }
  }

  static void _validateSqlite(File file) {
    final db = sqlite.sqlite3.open(file.path, mode: sqlite.OpenMode.readOnly);
    configureReadOnly(db);
    try {
      db.execute('PRAGMA query_only=ON');
      final integrity = db.select('PRAGMA integrity_check').first.values.first.toString();
      if (integrity.toLowerCase() != 'ok') {
        throw VectorMapInstallException('ABM map.sqlite integrity_check=$integrity');
      }
      final required = {
        'features', 'names', 'categories', 'search_fts', 'spatial',
        'node_data', 'way_data', 'segments', 'road_index', 'turn_restrictions',
      };
      final have = db.select("SELECT name FROM sqlite_master WHERE type IN ('table','view')")
          .map((r) => '${r['name']}').toSet();
      final missing = required.difference(have);
      if (missing.isNotEmpty) {
        throw VectorMapInstallException('ABM database is missing: ${missing.join(', ')}');
      }
      final nodes = (db.select('SELECT COUNT(*) c FROM node_data').first['c'] as num).toInt();
      final segments = (db.select('SELECT COUNT(*) c FROM segments').first['c'] as num).toInt();
      final ways = (db.select('SELECT COUNT(*) c FROM ways').first['c'] as num).toInt();
      final edges = (db.select('SELECT COUNT(*) c FROM edges').first['c'] as num).toInt();
      if (nodes == 0 || segments == 0 || ways == 0 || edges == 0) {
        throw const VectorMapInstallException('ABM routing graph is empty.');
      }
      // A country map cannot meaningfully contain one node/one segment. Do not
      // silently accept a truncated SQLite payload; surface it in diagnostics.
      if (nodes < 10 || segments < 10 || ways < 2 || edges < 2) {
        throw VectorMapInstallException(
          'ABM routing graph looks truncated: nodes=$nodes segments=$segments ways=$ways edges=$edges',
        );
      }
    } finally {
      db.dispose();
    }
  }

  Future<Map<String, List<AbmVectorFeature>>> loadViewport({
    required File containerFile,
    required AbmBBox bbox,
    required double zoom,
  }) async {
    final id = p.basenameWithoutExtension(containerFile.path);
    final artifacts = await prepare(containerFile: containerFile, id: id);
    await AbmDebugLog.addPoi(
      'VIEWPORT START id=$id zoom=${zoom.toStringAsFixed(2)} '
      'bbox=${bbox.minLat.toStringAsFixed(6)},${bbox.minLon.toStringAsFixed(6)}..'
      '${bbox.maxLat.toStringAsFixed(6)},${bbox.maxLon.toStringAsFixed(6)}',
    );
    final layers = await Isolate.run(() => _loadViewportLayers(artifacts.sqliteFile.path, bbox));
    final poi = layers['poi'] ?? const <AbmVectorFeature>[];
    final places = layers['places'] ?? const <AbmVectorFeature>[];
    final roads = layers['roads'] ?? const <AbmVectorFeature>[];
    await AbmDebugLog.addPoi('VIEWPORT RESULT poi=${poi.length} places=${places.length} roads=${roads.length}');
    for (final f in poi.take(12)) {
      final point = f.geometry.isEmpty || f.geometry.first.length < 2 ? const <double>[] : f.geometry.first;
      await AbmDebugLog.addPoi(
        'DRAW POI id=${f.id} name="${f.properties['name'] ?? f.properties['name_fa'] ?? ''}" '
        'cat="${f.properties['category'] ?? ''}" '
        'point=${point.length >= 2 ? '${point[1].toStringAsFixed(7)},${point[0].toStringAsFixed(7)}' : 'INVALID'}',
      );
    }
    return layers;
  }

  // POI روی نقشه‌ی آفلاین همیشه آیکن پیش‌فرض (abm-poi) می‌گیرد چون عبارت
  // icon-image در استایل، property به اسم `class` را با رشته‌های انگلیسیِ
  // خام تگ OSM (fuel, supermarket, ...) مقایسه می‌کند، اما اینجا آن property
  // مستقیماً از categories.name پر می‌شود که ممکن است NULL باشد (اگر
  // features.category_id ست نشده/به هیچ ردیفی در categories join نشود) یا
  // مقداری غیر از تگ خام باشد. یک‌بار در طول اجرا، مقادیر واقعیِ category
  // را برای چند POI اول لاگ می‌کنیم تا معلوم شود کدام حالت رخ می‌دهد.
  static bool _loggedPoiCategorySample = false;

  static Map<String, List<AbmVectorFeature>> _loadViewportLayers(String sqlitePath, AbmBBox bbox) {
    final db = sqlite.sqlite3.open(sqlitePath, mode: sqlite.OpenMode.readOnly);
    try {
      final out = <String, List<AbmVectorFeature>>{
        'places': <AbmVectorFeature>[],
        'poi': <AbmVectorFeature>[],
        'roads': <AbmVectorFeature>[],
      };
      final rows = db.select(
        'SELECT f.id,f.kind,f.category_id,c.name category,n.name,n.name_fa,n.name_en,f.opening_hours,'
        'CASE WHEN f.kind=0 THEN p.lat ELSE pl.lat END lat,'
        'CASE WHEN f.kind=0 THEN p.lon ELSE pl.lon END lon '
        'FROM spatial s JOIN features f ON f.id=s.id LEFT JOIN categories c ON c.id=f.category_id '
        'LEFT JOIN names n ON n.id=f.name_id '
        'LEFT JOIN poi p ON p.id=f.id AND f.kind=0 '
        'LEFT JOIN places pl ON pl.id=f.id AND f.kind=1 '
        'WHERE f.kind IN (0,1) AND s.max_lon>=? AND s.min_lon<=? AND s.max_lat>=? AND s.min_lat<=? '
        'AND ((f.kind=0 AND p.lat IS NOT NULL AND p.lon IS NOT NULL) OR (f.kind=1 AND pl.lat IS NOT NULL AND pl.lon IS NOT NULL)) '
        'ORDER BY f.id LIMIT 30000',
        [bbox.minLon, bbox.maxLon, bbox.minLat, bbox.maxLat],
      );
      if (!_loggedPoiCategorySample) {
        _loggedPoiCategorySample = true;
        final sample = rows
            .where((r) => (r['kind'] as num).toInt() == 0)
            .take(15)
            .map((r) => '${r['name'] ?? r['name_fa'] ?? ''}=cat_id:${r['category_id']},category:"${r['category']}"')
            .join(' | ');
        
      }
      for (final r in rows) {
        final lat = (r['lat'] as num).toDouble();
        final lon = (r['lon'] as num).toDouble();
        final kind = (r['kind'] as num).toInt() == 0 ? 'poi' : 'places';
        final category = '${r['category'] ?? ''}'.trim();
        out[kind]!.add(AbmVectorFeature(
          id: (r['id'] as num).toInt(),
          layer: kind,
          geometry: [[lon, lat]],
          bbox: AbmBBox(lon, lat, lon, lat),
          properties: <String, dynamic>{
            'name': '${r['name'] ?? ''}',
            'name_fa': '${r['name_fa'] ?? ''}',
            'name_en': '${r['name_en'] ?? ''}',
            'category': category,
            'class': category,
            'opening_hours': '${r['opening_hours'] ?? ''}',
          },
        ));
      }
      // Road names are deliberately stored in map.sqlite, not in the MVT
      // road tile attributes. Build a lightweight local GeoJSON road-label
      // layer from the spatial road index so every country uses its own OSM
      // local name (name), with language-specific fallbacks when available.
      final roadRows = db.select(
        'SELECT DISTINCT s.id,s.way_id,s.a,s.b,w.class_id,c.name class_name,w.name_id,w.speed_kmh,w.oneway,w.surface,'
        'n.name,n.name_fa,n.name_en,na.lat_e7 alat,na.lon_e7 alon,nb.lat_e7 blat,nb.lon_e7 blon '
        'FROM road_index r JOIN segments s ON s.id BETWEEN r.seg_from AND r.seg_to '
        'JOIN way_data w ON w.way_id=s.way_id LEFT JOIN categories c ON c.id=w.class_id LEFT JOIN names n ON n.id=w.name_id '
        'JOIN node_data na ON na.id=s.a JOIN node_data nb ON nb.id=s.b '
        'WHERE r.max_lon>=? AND r.min_lon<=? AND r.max_lat>=? AND r.min_lat<=? '
        // Was LIMIT 2500, ORDER BY s.way_id,s.id. In a dense residential
        // grid (many short named ways -- exactly the لاله/یاس/نیلوفر streets
        // in the sample viewport) that cap silently cut off whichever ways
        // happened to sort after it, so entire streets had zero segments
        // and never got a label. 20000 rows is still a single indexed
        // range scan (road_index -> segments), done once per viewport
        // refresh in an isolate, not per frame.
        'ORDER BY s.way_id,s.id LIMIT 20000',
        [bbox.minLon, bbox.maxLon, bbox.minLat, bbox.maxLat],
      );
      // Stitch each way's segments back into polylines by node-id adjacency
      // instead of by row order. The previous version only chained a row
      // onto the *end* of the line built so far (`line.last == a/b`); since
      // `ORDER BY s.id` has no guaranteed relationship to a segment's
      // position along the way, any segment that happened to arrive
      // out of geometric order broke the chain into its own disconnected
      // 2-point piece. A short, isolated 2-point line frequently has no
      // room for MapLibre to place a `symbol-placement: line` label at all
      // -- which is what "most street names don't render offline" was:
      // most ways were silently fragmented this way, not actually unnamed.
      final wayNodeA = <int, List<int>>{};
      final wayNodeB = <int, List<int>>{};
      final wayCoordA = <int, List<List<double>>>{};
      final wayCoordB = <int, List<List<double>>>{};
      final wayProps = <int, Map<String, dynamic>>{};
      for (final r in roadRows) {
        final wayId = (r['way_id'] as num).toInt();
        wayNodeA.putIfAbsent(wayId, () => <int>[]).add((r['a'] as num).toInt());
        wayNodeB.putIfAbsent(wayId, () => <int>[]).add((r['b'] as num).toInt());
        wayCoordA.putIfAbsent(wayId, () => <List<double>>[]).add(
          <double>[(r['alon'] as num).toDouble() * 1e-7, (r['alat'] as num).toDouble() * 1e-7],
        );
        wayCoordB.putIfAbsent(wayId, () => <List<double>>[]).add(
          <double>[(r['blon'] as num).toDouble() * 1e-7, (r['blat'] as num).toDouble() * 1e-7],
        );
        wayProps.putIfAbsent(wayId, () => <String, dynamic>{
          'name': '${r['name'] ?? ''}',
          'name_fa': '${r['name_fa'] ?? ''}',
          'name_en': '${r['name_en'] ?? ''}',
          'class': '${r['class_name'] ?? r['class_id'] ?? ''}',
          'oneway': (r['oneway'] as num?)?.toInt() == 1,
          'speed_kmh': (r['speed_kmh'] as num?)?.toInt(),
          'surface': '${r['surface'] ?? ''}',
        });
      }
      var roadId = -1;
      for (final wayId in wayProps.keys) {
        final name = '${wayProps[wayId]?['name'] ?? ''}'.trim();
        if (name.isEmpty) continue;
        final nodesA = wayNodeA[wayId]!;
        final nodesB = wayNodeB[wayId]!;
        final coordsA = wayCoordA[wayId]!;
        final coordsB = wayCoordB[wayId]!;
        final segCount = nodesA.length;
        final byNode = <int, List<int>>{};
        for (var i = 0; i < segCount; i++) {
          byNode.putIfAbsent(nodesA[i], () => <int>[]).add(i);
          byNode.putIfAbsent(nodesB[i], () => <int>[]).add(i);
        }
        final used = List<bool>.filled(segCount, false);
        for (var i = 0; i < segCount; i++) {
          if (used[i]) continue;
          used[i] = true;
          final chain = <List<double>>[coordsA[i], coordsB[i]];
          var frontNode = nodesA[i];
          var backNode = nodesB[i];
          var extended = true;
          while (extended) {
            extended = false;
            for (final j in byNode[backNode] ?? const <int>[]) {
              if (used[j]) continue;
              if (nodesA[j] == backNode) {
                chain.add(coordsB[j]);
                backNode = nodesB[j];
                used[j] = true;
                extended = true;
                break;
              } else if (nodesB[j] == backNode) {
                chain.add(coordsA[j]);
                backNode = nodesA[j];
                used[j] = true;
                extended = true;
                break;
              }
            }
          }
          extended = true;
          while (extended) {
            extended = false;
            for (final j in byNode[frontNode] ?? const <int>[]) {
              if (used[j]) continue;
              if (nodesA[j] == frontNode) {
                chain.insert(0, coordsB[j]);
                frontNode = nodesB[j];
                used[j] = true;
                extended = true;
                break;
              } else if (nodesB[j] == frontNode) {
                chain.insert(0, coordsA[j]);
                frontNode = nodesA[j];
                used[j] = true;
                extended = true;
                break;
              }
            }
          }
          if (chain.length < 2) continue;
          final minLon = chain.map((p) => p[0]).reduce((a, b) => a < b ? a : b);
          final maxLon = chain.map((p) => p[0]).reduce((a, b) => a > b ? a : b);
          final minLat = chain.map((p) => p[1]).reduce((a, b) => a < b ? a : b);
          final maxLat = chain.map((p) => p[1]).reduce((a, b) => a > b ? a : b);
          out['roads']!.add(AbmVectorFeature(
            id: roadId--,
            layer: 'roads',
            geometry: chain,
            bbox: AbmBBox(minLon, minLat, maxLon, maxLat),
            properties: wayProps[wayId]!,
            minZoom: 11,
          ));
        }
      }
      return out;
    } finally {
      db.dispose();
    }
  }
}
