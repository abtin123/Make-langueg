import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abtin_maps/core/geo/geo_types.dart';
import '../data/routing_service.dart';

import '../../map/presentation/destination_provider.dart';
import '../../gps/presentation/gps_providers.dart';
import '../../../shared/providers/abtinmap_providers.dart';
import '../../settings/presentation/appearance_settings_providers.dart';

final routingServiceProvider = Provider<RoutingService>((ref) {
  final service = RoutingService(ref);
  ref.onDispose(service.dispose);
  return service;
});

enum NavigationState {
  idle,
  calculating,
  navigating,
  error,
}

class ActiveNavigation {
  final RouteInfo route;
  final NavigationState state;
  final int currentInstructionIndex;
  final double remainingDistanceKm;
  final double distanceToNextManeuverM;
  final String? errorMessage;

  const ActiveNavigation({
    required this.route,
    this.state = NavigationState.navigating,
    this.currentInstructionIndex = 0,
    required this.remainingDistanceKm,
    this.distanceToNextManeuverM = 0,
    this.errorMessage,
  });

  ActiveNavigation copyWith({
    RouteInfo? route,
    NavigationState? state,
    int? currentInstructionIndex,
    double? remainingDistanceKm,
    double? distanceToNextManeuverM,
    String? errorMessage,
  }) {
    return ActiveNavigation(
      route: route ?? this.route,
      state: state ?? this.state,
      currentInstructionIndex:
          currentInstructionIndex ?? this.currentInstructionIndex,
      remainingDistanceKm: remainingDistanceKm ?? this.remainingDistanceKm,
      distanceToNextManeuverM:
          distanceToNextManeuverM ?? this.distanceToNextManeuverM,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  /// اگر مبدأ و مقصد روی یک گره‌ی گراف اسنپ شوند (مثلاً وقتی مکان ذخیره‌شده
  /// دقیقاً همان نقطه‌ی GPS فعلی است)، مسیر معتبر ولی با صفر دستور تولید
  /// می‌شود. قبلاً اینجا `route.instructions.last` روی لیست خالی صدا زده
  /// می‌شد که یک StateError پرتاب می‌کرد؛ چون این getter داخل build() صدا
  /// زده می‌شود، آن خطا در ریلیزِ اپ به‌صورت یک صفحه‌ی خاکستری (ErrorWidget
  /// پیش‌فرض فلاتر) دیده می‌شد. حالا برای این حالت یک دستور «رسیدید» ساختگی
  /// برگردانده می‌شود.
  static const _arrivedFallback = RouteInstruction(
    text: 'به مقصد رسیدید',
    distanceMeters: 0,
    location: LatLng(0, 0),
    type: 'arrive',
  );

  RouteInstruction get currentInstruction {
    if (route.instructions.isEmpty) return _arrivedFallback;
    if (currentInstructionIndex < route.instructions.length) {
      return route.instructions[currentInstructionIndex];
    }
    return route.instructions.last;
  }

  bool get hasArrived =>
      route.instructions.isEmpty ||
      currentInstructionIndex >= route.instructions.length - 1;
}

class ActiveNavigationNotifier extends StateNotifier<ActiveNavigation?> {
  ActiveNavigationNotifier() : super(null);

  void setNavigation(ActiveNavigation nav) {
    state = nav;
  }

  void updateProgress(int instructionIndex, double remainingDistance,
      {double? distanceToNextManeuverM}) {
    if (state != null) {
      state = state!.copyWith(
        currentInstructionIndex: instructionIndex,
        remainingDistanceKm: remainingDistance,
        distanceToNextManeuverM: distanceToNextManeuverM,
      );
    }
  }

  void clear() {
    state = null;
  }
}

final activeNavigationProvider =
    StateNotifierProvider<ActiveNavigationNotifier, ActiveNavigation?>((ref) {
  return ActiveNavigationNotifier();
});

/// حالت رانندگی: وقتی true باشد، نشانگر وسط صفحه ثابت می‌ماند و نقشه حرکت می‌کند
final drivingModeProvider = StateProvider<bool>((ref) => false);

final calculateRouteProvider =
    FutureProvider.autoDispose<RouteInfo?>((ref) async {
  // تغییر «منبع نقشه» باید محاسبهٔ جاری را هم عوض کند: آبتین‌مپ برای حالت
  // آفلاین و OSRM برای حالت آنلاین. بدون این watch، صفحهٔ مسیر نتیجهٔ موتور
  // قبلی را تا تغییر GPS یا مقصد نشان می‌داد.
  ref.watch(routingEngineProvider);
  final preferences = ref.watch(appearanceSettingsProvider);
  final destination = ref.watch(selectedDestinationProvider);
  // مهم: موقعیت GPS فقط یک snapshot برای شروع محاسبه است. اگر اینجا
  // `watch` شود، هر آپدیت GPS باعث invalidate شدن provider و محاسبهٔ دوبارهٔ
  // مسیر می‌شود؛ در نتیجه کارت مسیر بعد از پیدا شدن مسیر دوباره وارد
  // «در حال یافتن مسیرها…» می‌شود و می‌تواند چند محاسبهٔ هم‌زمان/هنگ ایجاد کند.
  // تا وقتی مقصد عوض نشده یا کاربر مسیر را شروع/لغو نکرده، همان نتیجه باید
  // ثابت بماند.
  final vehiclePosition = ref.read(vehiclePositionProvider).value;

  if (destination == null || vehiclePosition == null) {
    return null;
  }

  final routingService = ref.read(routingServiceProvider);

  return await routingService.calculateRoute(
    origin: LatLng(vehiclePosition.lat, vehiclePosition.lng),
    destination: destination.point,
    avoidUnpavedRoads: preferences.avoidUnpavedRoads,
    avoidTolls: preferences.avoidTolls,
  );
});

/// گزینه‌های واقعی مسیر برای صفحهٔ انتخاب. محاسبه فقط با تغییر مقصد،
/// موتور مسیریابی یا تنظیمات مؤثر انجام می‌شود؛ موقعیت GPS صرفاً snapshot
/// شروع محاسبه است و تغییرات بعدی GPS نباید تا زمان انتخاب/شروع کاربر،
/// دوباره مسیرها را محاسبه کنند.
final selectedRouteCandidateIndexProvider = StateProvider<int>((ref) => 0);

final calculateRoutesProvider =
    FutureProvider.autoDispose<List<RouteInfo>>((ref) async {
  ref.watch(routingEngineProvider);
  final preferences = ref.watch(appearanceSettingsProvider);
  final destination = ref.watch(selectedDestinationProvider);
  // موقعیت فقط برای snapshot مبدأ در لحظهٔ شروع محاسبه خوانده می‌شود.
  // `watch` کردن آن باعث می‌شد با هر فیکس GPS کل گزینه‌های مسیر دوباره
  // محاسبه شوند، حتی وقتی مسیر قبلی روی کارت آمادهٔ انتخاب کاربر بود.
  final vehiclePosition = ref.read(vehiclePositionProvider).value;
  if (destination == null || vehiclePosition == null) return const [];
  final routes = await ref.read(routingServiceProvider).calculateRoutes(
        origin: LatLng(vehiclePosition.lat, vehiclePosition.lng),
        destination: destination.point,
        avoidUnpavedRoads: preferences.avoidUnpavedRoads,
        avoidTolls: preferences.avoidTolls,
      );
  return rankRouteCandidates(routes, preferences.routePlanningMode);
});

List<RouteInfo> rankRouteCandidates(
  List<RouteInfo> routes,
  RoutePlanningMode mode,
) {
  final ranked = List<RouteInfo>.from(routes);
  if (ranked.length < 2) return ranked;
  switch (mode) {
    case RoutePlanningMode.fastest:
      ranked.sort((a, b) => a.durationMin.compareTo(b.durationMin));
    case RoutePlanningMode.shortest:
      ranked.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    case RoutePlanningMode.economic:
      final minDistance = ranked
          .map((route) => route.distanceKm)
          .reduce((a, b) => a < b ? a : b);
      final minDuration = ranked
          .map((route) => route.durationMin)
          .reduce((a, b) => a < b ? a : b);
      ranked.sort((a, b) {
        final scoreA = a.distanceKm / minDistance + a.durationMin / minDuration;
        final scoreB = b.distanceKm / minDistance + b.durationMin / minDuration;
        return scoreA.compareTo(scoreB);
      });
  }
  return ranked;
}
