import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../abtinmap/abm_map_service.dart';
import '../../routing/data/routing_provider.dart';
import '../../../shared/providers/abtinmap_providers.dart';
import '../../gps/presentation/gps_providers.dart';
import '../data/offline_place_search_service.dart';
import '../data/place_search_service.dart';

final searchActiveProvider = StateProvider<bool>((ref) => false);
final searchQueryProvider = StateProvider<String>((ref) => '');
final searchSelectedIndexProvider = StateProvider<int>((ref) => 0);
final _onlineSearchProvider =
    Provider<PlaceSearchService>((ref) => PlaceSearchService());
final _offlineSearchProvider = Provider<OfflinePlaceSearchService>(
    (ref) => OfflinePlaceSearchService(ref.watch(abmMapServiceProvider)));

/// Search follows the actual map mode. Online map => online search only.
/// Offline ABM map => local index only. We intentionally never merge the two
/// modes: this prevents a network result from appearing while the user is
/// navigating an offline map and prevents a missing offline index from
/// silently causing a network request.
final searchResultsProvider =
    FutureProvider.autoDispose<List<PlaceSearchResult>>((ref) async {
  final query = ref.watch(searchQueryProvider).trim();
  if (query.length < 2) return const [];

  await Future<void>.delayed(const Duration(milliseconds: 180));
  final current = ref.read(vehiclePositionProvider).valueOrNull;

  // HomeScreen falls back to the online renderer if the requested offline
  // engine has no complete vector ABM installed. Mirror that exact decision
  // here so search mode always matches the map that is actually visible.
  final requestedEngine = ref.watch(routingEngineProvider);
  final offlineReady = requestedEngine != RoutingEngine.online
      ? await ref
          .read(offlineAtlasReadyProvider.future)
          .catchError((_) => false)
      : false;

  if (offlineReady) {
    final result = await ref.read(_offlineSearchProvider).search(
          query,
          mapFileName: ref.read(abmActiveMapNameProvider),
          biasLat: current?.lat,
          biasLng: current?.lng,
        );
    ref.read(searchSelectedIndexProvider.notifier).state = 0;
    return result;
  }

  // Online mode is deliberately network-only. A failed network request is
  // an empty result, not a fallback to the local ABM index.
  final result = await ref
      .read(_onlineSearchProvider)
      .searchOnline(
        query,
        biasLat: current?.lat,
        biasLng: current?.lng,
      )
      .timeout(
        const Duration(seconds: 8),
        onTimeout: () => const <PlaceSearchResult>[],
      )
      .catchError((_) => <PlaceSearchResult>[]);
  ref.read(searchSelectedIndexProvider.notifier).state = 0;
  return result;
});
