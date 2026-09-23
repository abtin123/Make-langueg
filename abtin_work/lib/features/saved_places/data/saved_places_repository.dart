import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';

class SavedPlacesRepository {
  final AppDatabase db;
  SavedPlacesRepository(this.db);

  Stream<List<SavedPlace>> watchAll() {
    return (db.select(db.savedPlaces)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Stream<List<SavedPlace>> watchByCategory(String category) {
    return (db.select(db.savedPlaces)
          ..where((t) => t.category.equals(category))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Future<int> add({
    required String name,
    required double latitude,
    required double longitude,
    String? address,
    String category = 'favorite',
  }) {
    return db.into(db.savedPlaces).insert(
          SavedPlacesCompanion.insert(
            name: name,
            latitude: latitude,
            longitude: longitude,
            address: Value(address),
            category: Value(category),
          ),
        );
  }

  Future<void> remove(int id) {
    return (db.delete(db.savedPlaces)..where((t) => t.id.equals(id))).go();
  }

  Future<void> update(SavedPlace place) {
    return db.update(db.savedPlaces).replace(place);
  }

  Future<void> rename(
      {required int id, required String name, String? address}) {
    return (db.update(db.savedPlaces)..where((t) => t.id.equals(id))).write(
      SavedPlacesCompanion(
        name: Value(name),
        address: Value(address),
      ),
    );
  }
}
