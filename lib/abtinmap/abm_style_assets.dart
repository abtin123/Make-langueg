import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha1;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';


/// The one MapLibre style used by every map state (online/offline, day/night).
///
/// `assets/styles/abtin_unified_style.json` is the only place layers are
/// defined. It carries both data families -- OpenMapTiles (online) and the
/// ABM SQLite/GeoJSON sources (offline) -- and states its own conditions:
///  * `metadata["abm:source-modes"]` says which mode each source serves;
///  * a layer's `metadata["abm:offline"]` re-points that layer at an offline
///    source (buildings share one definition for both modes);
///  * `metadata["abm:palette"]` holds the day/night default colours that
///    `{{token}}` placeholders in offline-only layers resolve to.
///
/// MapLibre cannot switch a layer's data source with an expression, so the
/// condition is evaluated when the style is written: layers/sources that
/// don't serve the current mode are dropped from the output. Exactly one
/// generated style file exists at a time (content-hash named, see
/// [_writeStyle]), so any change of mode, theme or palette yields a new path.
class AbmStyleAssets {
  AbmStyleAssets._();

  static final AbmStyleAssets instance = AbmStyleAssets._();

  static const String _assetRevision = 'abtin-unified-maplibre-style-v3';
  static const String _bundledStyle = 'assets/styles/abtin_unified_style.json';
  static const List<String> _fontstacks = ['Vazirmatn', 'VazirmatnBold'];
  static const List<String> _ranges = [
    '0-255', '256-511', '1536-1791', '1792-2047', '8192-8447',
    '64256-64511', '64512-64767', '65024-65279', '65280-65535',
  ];

  Directory? _root;

  Future<Directory> _ensureRoot() async {
    if (_root != null) return _root!;
    final base = await getApplicationSupportDirectory();
    final root = Directory('${base.path}/abm_style/$_assetRevision');
    await root.create(recursive: true);

    for (final stack in _fontstacks) {
      final dir = Directory('${root.path}/glyphs/$stack');
      await dir.create(recursive: true);
      for (final range in _ranges) {
        await _copyAsset(
          'assets/glyphs/$stack/$range.pbf',
          File('${dir.path}/$range.pbf'),
        );
      }
    }

    final spriteDir = Directory('${root.path}/sprites');
    await spriteDir.create(recursive: true);
    for (final name in const [
      'abtin.json', 'abtin.png', 'abtin@2x.json', 'abtin@2x.png',
    ]) {
      await _copyAsset('assets/sprites/$name', File('${spriteDir.path}/$name'));
    }
    _root = root;
    return root;
  }

  Future<void> _copyAsset(String assetPath, File target) async {
    final data = await rootBundle.load(assetPath);
    await target.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
  }

  String _hex(String value) => value.startsWith('#') ? value : '#$value';

  Map<String, dynamic> _copyStyle(Map<String, dynamic> raw) =>
      jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;

  /// The bundled base style (built for a global OpenMapTiles basemap) shows
  /// every place/POI/road/water name as `"latin-transliteration Persian"`
  /// whenever the source tile has a `name:nonlatin` value -- a global
  /// bilingual convention that, for an Iran-focused app reading mostly
  /// Persian OSM data, means every label prints a second, often
  /// low-quality auto-transliterated Latin string in front of the real
  /// name. That's very likely what read as "names aren't displaying
  /// correctly": not a missing label, but every label showing extra noise.
  ///
  /// Offline already only ever shows one name (`coalesce(name, name_fa,
  /// name_en)`). Rewriting the same `case`/`concat` pattern here, before
  /// online/offline branch at all, means text logic no longer has two
  /// separate implementations to keep in sync -- online and offline read
  /// the exact same simplified expression.
  void _localizeTextFields(Map<String, dynamic> style) {
    bool isBilingualConcat(dynamic textField) {
      if (textField is! List || textField.length < 3 || textField[0] != 'case') {
        return false;
      }
      final thenBranch = textField[2];
      return thenBranch is List && thenBranch.isNotEmpty && thenBranch[0] == 'concat';
    }

    final layers = <Map<String, dynamic>>[];
    for (final raw in (style['layers'] as List? ?? const [])) {
      final layer = Map<String, dynamic>.from(raw as Map);
      final layout = Map<String, dynamic>.from(
        (layer['layout'] as Map? ?? const {}).map((k, v) => MapEntry('$k', v)),
      );
      if (isBilingualConcat(layout['text-field'])) {
        layout['text-field'] = <dynamic>[
          'coalesce',
          <dynamic>['get', 'name'],
          <dynamic>['get', 'name:nonlatin'],
          <dynamic>['get', 'name_en'],
          <dynamic>['get', 'name:latin'],
        ];
        layer['layout'] = layout;
      }
      layers.add(layer);
    }
    style['layers'] = layers;
  }

  void _applyPalette(
    Map<String, dynamic> style, {
    required Map<String, String> colors,
    required bool dark,
    String? roadDirectionArrowColorHex,
    double? roadDirectionArrowSizePercent,
  }) {
    final layers = <Map<String, dynamic>>[];
    for (final raw in (style['layers'] as List? ?? const [])) {
      final layer = Map<String, dynamic>.from(raw as Map);
      // Offline-only layers take their colours from `{{token}}` placeholders
      // (resolved from the style's own palette), not from the heuristics below.
      if (_asMap(layer['metadata'])['abm:tokens'] == true) {
        layers.add(layer);
        continue;
      }
      final paint = Map<String, dynamic>.from(
        (layer['paint'] as Map? ?? const {}).map(
          (k, v) => MapEntry('$k', v),
        ),
      );
      final layout = Map<String, dynamic>.from(
        (layer['layout'] as Map? ?? const {}).map(
          (k, v) => MapEntry('$k', v),
        ),
      );
      final type = '${layer['type'] ?? ''}';
      final id = '${layer['id'] ?? ''}'.toLowerCase();
      final sourceLayer = '${layer['source-layer'] ?? ''}'.toLowerCase();
      final source = '${layer['source'] ?? ''}';
      String pick(String key, String _) { final value = colors[key]; if (value == null || value.isEmpty) throw StateError('Missing map palette color: $key'); return _hex(value); }

      if (type == 'background') {
        paint['background-color'] = pick('background', '');
      }

      if (id == 'road_one_way_arrow' || id == 'road_one_way_arrow_opposite') {
        paint['icon-color'] = _hex(roadDirectionArrowColorHex ?? colors['label']!);
        layout['icon-size'] =
            ((roadDirectionArrowSizePercent ?? 70.0) / 100.0)
                .clamp(0.3, 2.0)
                .toDouble();
        layout['icon-allow-overlap'] = true;
        layer['layout'] = layout;
      }

      if (type == 'fill' || type == 'fill-extrusion') {
        if (sourceLayer == 'water' || sourceLayer == 'waterway') {
          paint[type == 'fill-extrusion' ? 'fill-extrusion-color' : 'fill-color'] =
              pick('water', '');
        } else if (sourceLayer == 'park' || sourceLayer == 'landcover') {
          paint[type == 'fill-extrusion' ? 'fill-extrusion-color' : 'fill-color'] =
              pick('green', '');
        } else if (sourceLayer == 'landuse') {
          paint[type == 'fill-extrusion' ? 'fill-extrusion-color' : 'fill-color'] =
              pick('urban', '');
        } else if (sourceLayer == 'building') {
          paint[type == 'fill-extrusion' ? 'fill-extrusion-color' : 'fill-color'] =
              pick('building', '');
          if (paint.containsKey('fill-outline-color')) {
            paint['fill-outline-color'] =
                pick('building', '');
          }
        }
      }

      if (type == 'line' && sourceLayer == 'transportation') {
        if (id.contains('casing') || id.contains('hatching')) {
          paint['line-color'] = pick('roadOutline', '');
        } else if (id.contains('motorway')) {
          paint['line-color'] = pick('roadMotorway', '');
        } else if (id.contains('trunk')) {
          paint['line-color'] = pick('roadTrunk', '');
        } else if (id.contains('primary')) {
          paint['line-color'] = pick('roadPrimary', '');
        } else if (id.contains('secondary') || id.contains('tertiary')) {
          paint['line-color'] = pick('roadSecondary', '');
        } else {
          paint['line-color'] = pick('roadLocal', '');
        }
      }

      if (type == 'line' && sourceLayer == 'boundary') {
        paint['line-color'] = pick('roadOutline', '');
      }

      if (type == 'symbol') {
        // Offline's hand-authored `poi-points`/`poi-labels` (source
        // `abm-poi`) carry no `source-layer`, so they must be recognized by
        // source id too -- otherwise they fall into the `label` bucket
        // instead of `poi` and never pick up the user's POI color.
        final isPoi = sourceLayer == 'poi' || source == 'abm-poi';
        if (paint.containsKey('text-color')) {
          paint['text-color'] = pick(isPoi ? 'poi' : 'label', '');
        }
        if (paint.containsKey('text-halo-color')) {
          paint['text-halo-color'] = pick('halo', '');
        }
      }

      layer['paint'] = paint;
      layers.add(layer);
    }
    style['layers'] = layers;
  }

  void _setLocalFontsAndAssets(
    Map<String, dynamic> style,
    Directory root,
  ) {
    style['glyphs'] =
        'file://${root.path}/glyphs/{fontstack}/{range}.pbf';
    style['sprite'] = 'file://${root.path}/sprites/abtin';
    for (final raw in (style['layers'] as List? ?? const [])) {
      final layer = Map<String, dynamic>.from(raw as Map);
      final layout = Map<String, dynamic>.from(
        (layer['layout'] as Map? ?? const {}).map(
          (k, v) => MapEntry('$k', v),
        ),
      );
      final fonts = layout['text-font'];
      if (fonts is List) {
        layout['text-font'] = fonts.map((font) {
          final value = '$font'.toLowerCase();
          return value.contains('bold') ? 'VazirmatnBold' : 'Vazirmatn';
        }).toList();
        layer['layout'] = layout;
      }
      final index = (style['layers'] as List).indexOf(raw);
      (style['layers'] as List)[index] = layer;
    }
  }

  Map<String, dynamic> _asMap(dynamic value) => value is Map
      ? Map<String, dynamic>.from(value.map((k, v) => MapEntry('$k', v)))
      : <String, dynamic>{};

  /// Keeps only what the current mode can draw. A layer stays when its
  /// source serves this mode (or both), it has no source (background), or --
  /// offline -- it declares an `abm:offline` override.
  void _selectMode(Map<String, dynamic> style, {required bool offline}) {
    final modes = _asMap(_asMap(style['metadata'])['abm:source-modes']);
    final want = offline ? 'offline' : 'online';
    final kept = <Map<String, dynamic>>[];
    for (final raw in (style['layers'] as List? ?? const [])) {
      final layer = Map<String, dynamic>.from(raw as Map);
      final source = layer['source'];
      final mode = source == null ? 'both' : '${modes['$source'] ?? 'both'}';
      final hasOfflineOverride =
          _asMap(_asMap(layer['metadata'])['abm:offline']).isNotEmpty;
      if (mode == 'both' || mode == want || (offline && hasOfflineOverride)) {
        kept.add(layer);
      }
    }
    style['layers'] = kept;
  }

  /// Offline: re-point layers that declare `abm:offline` (e.g. buildings)
  /// at the offline source. Runs after [_applyPalette], which still keys
  /// its colour rules off the online source-layer name.
  /// Offline rendering is SQLite-backed. The canonical database is queried
  /// into the GeoJSON sources (`abm-roads`, `abm-poi`, `abm-places`) by the
  /// viewport reader. Legacy MBTiles layers are deliberately removed instead
  /// of being opened as a second data store.
  void _applyOfflineOverrides(Map<String, dynamic> style) {
    final layers = <Map<String, dynamic>>[];
    for (final raw in (style['layers'] as List? ?? const [])) {
      final layer = Map<String, dynamic>.from(raw as Map);
      final source = '${layer['source'] ?? ''}';
      if (source == 'abm-tiles') {
        final sourceLayer = '${layer['source-layer'] ?? ''}';
        if (sourceLayer == 'roads') {
          // The SQLite viewport reader supplies LineString road geometry.
          layer['source'] = 'abm-roads';
          layer.remove('source-layer');
          layers.add(layer);
        }
        // Water/landuse/building/boundary MBTiles layers have no second
        // backing store in SQLite-only mode, so do not leave dangling source
        // references in the generated style.
        continue;
      }
      final offlineOverride = _asMap(_asMap(layer['metadata'])['abm:offline']);
      if (offlineOverride.isNotEmpty) {
        // Building layers used to point at abm-tiles through this override.
        // Drop them here rather than producing an invalid style.
        final overriddenSource = '${offlineOverride['source'] ?? ''}';
        if (overriddenSource == 'abm-tiles') continue;
        layer.addAll(offlineOverride);
      }
      layers.add(layer);
    }
    style['layers'] = layers;
  }

  /// Apply the same user-selected palette to the online vector tiles too.
  /// The previous implementation only recoloured a subset of transportation
  /// layers; many OpenFreeMap layers kept their baked light colours, which is
  /// why Online could remain light while Offline was dark. This pass is
  /// deliberately source-layer/id based and covers the full basemap family.
  void _applyOnlinePalette(Map<String, dynamic> style, {
    required Map<String, String> palette,
    required bool dark,
  }) {
    String hex(String key) { final value = palette[key]; if (value == null || value.isEmpty) throw StateError('Missing map palette color: $key'); return _hex(value); }
    final layers = <Map<String, dynamic>>[];
    for (final raw in (style['layers'] as List? ?? const [])) {
      final layer = Map<String, dynamic>.from(raw as Map);
      final source = '${layer['source'] ?? ''}';
      if (source != 'openmaptiles') {
        layers.add(layer);
        continue;
      }
      final type = '${layer['type'] ?? ''}';
      final id = '${layer['id'] ?? ''}'.toLowerCase();
      final sourceLayer = '${layer['source-layer'] ?? ''}'.toLowerCase();
      final paint = Map<String, dynamic>.from(
        (layer['paint'] as Map? ?? const {}).map((k, v) => MapEntry('$k', v)),
      );

      if (type == 'background') {
        paint['background-color'] = hex('background');
      } else if (type == 'fill' || type == 'fill-extrusion') {
        final key = sourceLayer == 'water' || sourceLayer == 'waterway'
            ? 'water'
            : (sourceLayer == 'park' || sourceLayer == 'landcover'
                ? 'green'
                : (sourceLayer == 'building' ? 'building' : 'urban'));
        final colorKey = type == 'fill-extrusion' ? 'fill-extrusion-color' : 'fill-color';
        paint[colorKey] = hex(key);
        if (paint.containsKey('fill-outline-color')) {
          paint['fill-outline-color'] = hex(key == 'building' ? 'building' : 'roadOutline');
        }
      } else if (type == 'line' && sourceLayer == 'transportation') {
        final isCasing = id.contains('casing') || id.contains('hatching');
        final key = isCasing
            ? 'roadOutline'
            : id.contains('motorway')
                ? 'roadMotorway'
                : id.contains('trunk')
                    ? 'roadTrunk'
                    : id.contains('primary')
                        ? 'roadPrimary'
                        : (id.contains('secondary') || id.contains('tertiary'))
                            ? 'roadSecondary'
                            : 'roadLocal';
        paint['line-color'] = hex(key);
      } else if (type == 'line' && (sourceLayer == 'boundary' || sourceLayer == 'transportation_name')) {
        paint['line-color'] = hex('roadOutline');
      } else if (type == 'symbol') {
        if (paint.containsKey('text-color')) {
          paint['text-color'] = hex('label');
        }
        if (paint.containsKey('text-halo-color')) {
          paint['text-halo-color'] = hex('halo');
        }
        if (id.startsWith('poi_') && paint.containsKey('icon-color')) {
          paint['icon-color'] = hex('poi');
        }
      }
      layer['paint'] = paint;
      layers.add(layer);
    }
    style['layers'] = layers;
  }

  static final RegExp _paletteToken = RegExp(r'^\{\{(\w+)\}\}$');

  /// Replaces every `"{{name}}"` string with a colour: the user's palette
  /// wins, the style's own day/night default fills any gap.
  dynamic _resolveTokens(dynamic node, Map<String, String> palette) {
    if (node is String) {
      final match = _paletteToken.firstMatch(node);
      if (match == null) return node;
      final value = palette[match.group(1)!];
      if (value == null) throw StateError('Unknown style palette token: $node');
      return _hex(value);
    }
    if (node is List) {
      return node.map((e) => _resolveTokens(e, palette)).toList();
    }
    if (node is Map) {
      return node.map((k, v) => MapEntry('$k', _resolveTokens(v, palette)));
    }
    return node;
  }

  /// Drops sources with no remaining layer reads. Offline mode therefore
  /// cannot accidentally retain an online OpenMapTiles source.
  void _pruneSources(Map<String, dynamic> style) {
    final used = <String>{};
    for (final raw in (style['layers'] as List? ?? const [])) {
      final source = (raw as Map)['source'];
      if (source != null) used.add('$source');
    }
    final sources = _asMap(style['sources']);
    sources.removeWhere((key, _) => !used.contains(key));
    style['sources'] = sources;
  }

  String? _currentStyleFile;
  String? _previousStyleFile;

  /// Writes the style under a name derived from its own content, so a
  /// different mode/theme/palette always means a different path -- the map
  /// widget is keyed on that path and rebuilds on change without the app
  /// having to be restarted. Only the current and the previous file are
  /// kept (the previous one may still be referenced while the widget swaps).
  Future<String> _writeStyle(Directory root, String body) async {
    final hash = sha1.convert(utf8.encode(body)).toString().substring(0, 12);
    final name = 'style_$hash.json';
    final file = File('${root.path}/$name');
    await file.writeAsString(body, flush: true);
    if (name != _currentStyleFile) {
      _previousStyleFile = _currentStyleFile;
      _currentStyleFile = name;
    }
    try {
      await for (final entity in root.list(followLinks: false)) {
        if (entity is! File) continue;
        final base = entity.uri.pathSegments.last;
        if (!base.startsWith('style_') || !base.endsWith('.json')) continue;
        if (base == _currentStyleFile || base == _previousStyleFile) continue;
        try {
          await entity.delete();
        } catch (_) {}
      }
    } catch (error) {
      
    }
    return file.path;
  }

  /// Builds the style for the current state and returns its file path.
  /// [offline] selects the SQLite-backed offline rendering mode.
  Future<String> resolve({
    required bool dark,
    required Map<String, String> colors,
    String? roadDirectionArrowColorHex,
    double? roadDirectionArrowSizePercent,
    bool offline = false,
  }) async {
    final root = await _ensureRoot();
    final raw = await rootBundle.loadString(_bundledStyle);
    final style = _copyStyle(jsonDecode(raw) as Map<String, dynamic>);

    // Map colours come exclusively from the Appearance/Map settings.
    // The bundled style intentionally contains no colour defaults.
    final palette = <String, String>{...colors};

    _selectMode(style, offline: offline);
    _localizeTextFields(style);
    _applyPalette(
      style,
      colors: palette,
      dark: dark,
      roadDirectionArrowColorHex: roadDirectionArrowColorHex,
      roadDirectionArrowSizePercent: roadDirectionArrowSizePercent,
    );
    _applyOnlinePalette(style, palette: palette, dark: dark);
    if (offline) _applyOfflineOverrides(style);
    style['layers'] = _resolveTokens(style['layers'], palette);
    _pruneSources(style);
    _setLocalFontsAndAssets(style, root);

    style['metadata'] = <String, dynamic>{
      'abtin_maps_unified_style': true,
      'abtin_maps_offline_sources': offline,
      'abtin_maps_theme': dark ? 'night' : 'day',
      'abtin_maps_renderer': 'MapLibre Native',
    };

    final path = await _writeStyle(root, jsonEncode(style));
    
    return path;
  }

  Future<String> resolveStyle(String assetPath) async => assetPath;
}
