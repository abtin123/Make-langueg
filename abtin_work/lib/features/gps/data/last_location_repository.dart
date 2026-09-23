import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';

class LastLocationRepository {
  final AppDatabase db;
  const LastLocationRepository(this.db);

  static const _rowId = 1;

  Future<LastKnownLocationData?> getLast() async {
    return (db.select(db.lastKnownLocation)..where((t) => t.id.equals(_rowId)))
        .getSingleOrNull();
  }

  Future<void> save({
    required double lat,
    required double lng,
    double? heading,
    double? speedKmh,
    double? accuracy,
  }) async {
    await db.into(db.lastKnownLocation).insertOnConflictUpdate(
          LastKnownLocationCompanion.insert(
            id: const Value(_rowId),
            latitude: lat,
            longitude: lng,
            heading: Value(heading),
            speedKmh: Value(speedKmh),
            accuracy: Value(accuracy),
          ),
        );
  }
}
