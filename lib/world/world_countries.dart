import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Decodes the bundled world country boundary dataset
/// (`assets/world/world_boundaries.v1.json.gz`) into a GeoJSON
/// FeatureCollection that MapLibre can render directly as a `world-countries`
/// source, giving the offline map a complete globe (every country, real
/// borders) instead of a handful of hand-drawn placeholder shapes.
///
/// File format (gzip-compressed JSON):
/// ```json
/// { "v": 1, "s": 10000, "b": [ [ ring, ring, ... ], ... ] }
/// ```
/// * `s` is the fixed-point scale: divide every coordinate by `s` to get
///   degrees.
/// * `b` is one entry per country. Each entry is a list of closed rings
///   (outer boundaries and, where present, island/enclave rings that were
///   not distinguished during export).
/// * The first point of each ring is absolute `[lon*s, lat*s]` (rounded to
///   integers); every following point is a delta from the previous point,
///   which keeps the file small. Coordinates must be summed cumulatively
///   before dividing by `s`.
class WorldCountries {
  WorldCountries._();

  static const String assetPath = 'assets/world/world_boundaries.v1.json.gz';

  static Map<String, dynamic>? _cached;
  static Future<Map<String, dynamic>>? _loading;

  /// Returns the world countries as a GeoJSON FeatureCollection of
  /// MultiPolygon features (one feature per country). Cached after the
  /// first call.
  static Future<Map<String, dynamic>> load() {
    final cached = _cached;
    if (cached != null) return Future.value(cached);
    return _loading ??= _load().then((value) {
      _cached = value;
      _loading = null;
      return value;
    });
  }

  static Future<Map<String, dynamic>> _load() async {
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final decoded = _decode(bytes);
    return decoded;
  }

  static Map<String, dynamic> _decode(Uint8List gzipped) {
    final jsonBytes = GZipDecoder().decodeBytes(gzipped, verify: false);
    final raw = jsonDecode(utf8.decode(jsonBytes));
    if (raw is! Map || raw['b'] is! List) {
      return {'type': 'FeatureCollection', 'features': <dynamic>[]};
    }
    final scale = (raw['s'] as num?)?.toDouble() ?? 10000.0;
    final countries = raw['b'] as List;

    final features = <dynamic>[];
    for (final rawCountry in countries) {
      if (rawCountry is! List) continue;
      final polygons = <dynamic>[];
      for (final rawRing in rawCountry) {
        if (rawRing is! List || rawRing.length < 3) continue;
        final ring = _decodeRing(rawRing, scale);
        if (ring.length < 4) continue;
        // Each ring is treated as an independent exterior polygon. The
        // export format does not flag holes, so nested rings (rare lake or
        // enclave cutouts) render as solid land; every coastline and land
        // border is still complete and correctly placed.
        polygons.add([ring]);
      }
      if (polygons.isEmpty) continue;
      features.add({
        'type': 'Feature',
        'properties': const <String, dynamic>{},
        'geometry': {'type': 'MultiPolygon', 'coordinates': polygons},
      });
    }
    return {'type': 'FeatureCollection', 'features': features};
  }

  static List<List<double>> _decodeRing(List rawRing, double scale) {
    final ring = <List<double>>[];
    var x = 0;
    var y = 0;
    for (var i = 0; i < rawRing.length; i++) {
      final point = rawRing[i];
      if (point is! List || point.length < 2) continue;
      final dx = (point[0] as num).toInt();
      final dy = (point[1] as num).toInt();
      if (i == 0) {
        x = dx;
        y = dy;
      } else {
        x += dx;
        y += dy;
      }
      ring.add([x / scale, y / scale]);
    }
    if (ring.isEmpty) return ring;
    final first = ring.first;
    final last = ring.last;
    if (first[0] != last[0] || first[1] != last[1]) {
      ring.add(List<double>.from(first));
    }
    return ring;
  }
}
