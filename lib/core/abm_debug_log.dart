import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// One compact diagnostic channel for the complete offline POI + routing path.
/// It is intentionally silent in the UI and persistent on disk so a failed
/// navigation/search attempt can be shared after the fact.
class AbmDebugLog {
  static const int _maxLogs = 2500;
  static final List<String> _logs = <String>[];

  static List<String> get logs => List.unmodifiable(_logs.reversed);
  static List<String> get gpsLogs => logs; // compatibility with old callers

  static Future<void> addRouting(String text) => _add('ROUTING', text);
  static Future<void> addPoi(String text) => _add('POI', text);
  static Future<void> addMap(String text) => _add('MAP', text);

  static Future<void> _add(String channel, String text) async {
    final line = '[${DateTime.now().toIso8601String()}][$channel] $text';
    _logs.add(line);
    if (_logs.length > _maxLogs) {
      _logs.removeRange(0, _logs.length - _maxLogs);
    }
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/routing_poi_debug.log');
      await file.writeAsString('$line\n', mode: FileMode.append, flush: false);
    } catch (_) {
      // Diagnostics must never break POI search or navigation.
    }
  }

  static void clear() => _logs.clear();
  static void clearGps() => clear(); // compatibility with old callers
}
