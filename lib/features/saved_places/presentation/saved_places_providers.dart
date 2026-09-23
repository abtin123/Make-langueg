import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_provider.dart';
import '../data/saved_places_repository.dart';

export '../../../core/database/database_provider.dart' show appDatabaseProvider;

final savedPlacesRepositoryProvider = Provider<SavedPlacesRepository>((ref) {
  return SavedPlacesRepository(ref.watch(appDatabaseProvider));
});

final savedPlacesListProvider = StreamProvider((ref) {
  return ref.watch(savedPlacesRepositoryProvider).watchAll();
});
