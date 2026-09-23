import 'dart:io';
import 'package:sqlite3/sqlite3.dart';

class SearchResult {
  const SearchResult(
      {required this.name,
      required this.category,
      required this.latitude,
      required this.longitude,
      this.distanceMeters});
  final String name, category;
  final double latitude, longitude;
  final double? distanceMeters;
}

class AbmSearchEngine {
  Future<List<SearchResult>> search(File dbFile, String query,
      {int limit = 20}) async {
    if (!await dbFile.exists() || query.trim().length < 2) return const [];
    final db = sqlite3.open(dbFile.path, mode: OpenMode.readOnly);
    try {
      final tables = db.select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='search_fts'");
      if (tables.isEmpty) return const [];
      final q = query
          .trim()
          .replaceAll('"', ' ')
          .split(RegExp(r'\s+'))
          .where((x) => x.isNotEmpty)
          .map((x) => '"${x.replaceAll('"', '""')}"*')
          .join(' AND ');
      final rows = db.select(
          'SELECT p.name, p.category, p.lat, p.lon FROM search_fts f JOIN places p ON p.id=f.rowid WHERE search_fts MATCH ? LIMIT ?',
          [q, limit]);
      return [
        for (final r in rows)
          SearchResult(
              name: '${r['name'] ?? ''}',
              category: '${r['category'] ?? ''}',
              latitude: (r['lat'] as num).toDouble(),
              longitude: (r['lon'] as num).toDouble())
      ];
    } finally {
      db.dispose();
    }
  }
}
