import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_provider.dart';
import '../data/last_location_repository.dart';

final lastLocationRepositoryProvider = Provider<LastLocationRepository>((ref) {
  return LastLocationRepository(ref.watch(appDatabaseProvider));
});
