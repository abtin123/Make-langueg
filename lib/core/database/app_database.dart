import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class SavedPlaces extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  TextColumn get address => text().nullable()();
  TextColumn get category => text().withDefault(const Constant('favorite'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class RouteHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  RealColumn get startLat => real()();
  RealColumn get startLng => real()();
  RealColumn get endLat => real()();
  RealColumn get endLng => real()();
  TextColumn get endLabel => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

class LastKnownLocation extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  RealColumn get heading => real().nullable()();
  RealColumn get speedKmh => real().nullable()();
  RealColumn get accuracy => real().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class SearchHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get query => text()();
  TextColumn get title => text()();
  TextColumn get subtitle => text().nullable()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  BoolColumn get isOffline => boolean().withDefault(const Constant(false))();
  DateTimeColumn get searchedAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(tables: [
  SavedPlaces,
  RouteHistory,
  AppSettings,
  LastKnownLocation,
  SearchHistory
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(appSettings);
          }
          if (from < 3) {
            await m.createTable(lastKnownLocation);
          }
          if (from < 4) {
            await m.createTable(searchHistory);
          }
          if (from < 6) {
            await m.database.customStatement('DROP TABLE IF EXISTS users');
          }
        },
      );

  /// Add a search to history
  Future<void> addSearchToHistory({
    required String query,
    required String title,
    String? subtitle,
    required double latitude,
    required double longitude,
    required bool isOffline,
  }) async {
    await into(searchHistory).insert(
      SearchHistoryCompanion(
        query: Value(query),
        title: Value(title),
        subtitle: Value(subtitle),
        latitude: Value(latitude),
        longitude: Value(longitude),
        isOffline: Value(isOffline),
      ),
    );
  }

  /// Get recent searches
  Future<List<SearchHistoryData>> getRecentSearches({int limit = 10}) async {
    return (select(searchHistory)
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.searchedAt, mode: OrderingMode.desc)
          ])
          ..limit(limit))
        .get();
  }

  /// Remove a single search-history row by its id (برای دکمهٔ × کنار هر
  /// آیتم در «جستجوهای اخیر»؛ برخلاف [clearSearchHistory] که همه را پاک
  /// می‌کند، این متد فقط یک ردیف را حذف می‌کند).
  Future<void> deleteSearchHistoryItem(int id) async {
    await (delete(searchHistory)..where((t) => t.id.equals(id))).go();
  }

  /// Clear search history
  Future<void> clearSearchHistory() async {
    await delete(searchHistory).go();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'abtin_maps.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
