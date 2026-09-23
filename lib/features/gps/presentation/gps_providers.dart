import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/permissions/location_permission_flow.dart';
import '../../../shared/providers/abtinmap_providers.dart';
import '../data/location_repository.dart';
import '../data/location_service.dart';
import 'last_location_providers.dart';
import 'navigation_position_controller.dart';

final locationServiceProvider = Provider<LocationService>((ref) {
  final service = LocationService();
  ref.onDispose(service.dispose);
  return service;
});

/// لایه‌ی رسمی LocationRepository طبق معماری هدف
/// (LocationService → LocationRepository → ... → Map UI). امضای start/pause
/// اینجاست تا کنترلرهای بالادستی (مثل NavigationPositionController) دیگر
/// مستقیم با LocationService کار نکنند.
final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  final service = ref.watch(locationServiceProvider);
  // service.dispose() is already wired via locationServiceProvider's own
  // onDispose — don't register it a second time here, StreamController
  // .close() throws if called twice.
  return LocationRepository(service);
});

final locationLifecycleTickProvider = StateProvider<int>((ref) => 0);

/// LocationState صریح (waiting/active/unavailable) — تا UI بدون خواندن
/// AbmDebugLog بتواند مستقیم روی وضعیت GPS سوییچ کند.
final locationStateProvider = StreamProvider<LocationState>((ref) {
  final service = ref.watch(locationServiceProvider);
  return Stream<LocationState>.multi((controller) {
    controller.add(service.state);
    final sub = service.stateStream.listen(controller.add);
    controller.onCancel = sub.cancel;
  });
});

final locationReadinessProvider =
    StreamProvider<LocationReadiness>((ref) async* {
  final locationService = ref.read(locationServiceProvider);
  bool serviceStarted = false;

  Future<LocationReadiness> reportAndMaybeStart(LocationReadiness r) async {
    if (r == LocationReadiness.ready && !serviceStarted) {
      serviceStarted = true;
      locationService.start();
    }
    return r;
  }

  yield await reportAndMaybeStart(await LocationPermissionFlow.ensureReady());

  final serviceStatusStream = Geolocator.getServiceStatusStream();

  final lifecycleStream =
      ref.watch(locationLifecycleTickProvider.notifier).stream;

  await for (final _ in _merge(serviceStatusStream, lifecycleStream)) {
    yield await reportAndMaybeStart(
      await LocationPermissionFlow.checkStatusAndRetryIfDenied(),
    );
  }
});

final retryLocationPermissionProvider =
    Provider<Future<void> Function()>((ref) {
  return () async {
    await LocationPermissionFlow.retryFromUserTap();
    ref.read(locationLifecycleTickProvider.notifier).state++;
  };
});

Stream<void> _merge(Stream<ServiceStatus> a, Stream<int> b) {
  final controller = StreamController<void>();
  final subA = a.listen((_) => controller.add(null));
  final subB = b.listen((_) => controller.add(null));
  controller.onCancel = () {
    subA.cancel();
    subB.cancel();
  };
  return controller.stream;
}

final vehiclePositionProvider = StreamProvider<VehiclePosition>((ref) {
  ref.watch(locationReadinessProvider);
  final stream = ref.watch(locationServiceProvider).stream;

  DateTime lastSaved = DateTime.fromMillisecondsSinceEpoch(0);
  final repo = ref.read(lastLocationRepositoryProvider);
  final broadcast = stream.asBroadcastStream();
  final persistenceSub = broadcast.listen((pos) {
    final now = DateTime.now();
    if (now.difference(lastSaved) >= const Duration(seconds: 5)) {
      lastSaved = now;
      repo.save(
        lat: pos.lat,
        lng: pos.lng,
        heading: pos.headingDeg,
        speedKmh: pos.speedKmh,
        accuracy: pos.accuracyM,
      );
    }
  });
  ref.onDispose(persistenceSub.cancel);

  return broadcast;
});

final lastKnownLocationFromDbProvider = FutureProvider((ref) async {
  return ref.watch(lastLocationRepositoryProvider).getLast();
});

/// آخرین لایه‌ی pipeline — «Map Matching» — طبق معماری هدف. گراف واقعی
/// از [abmFileProvider] (نقشه‌ی آفلاین بازِ فعلی) ساخته می‌شود؛ اگر نقشه
/// هنوز باز نشده یا نصب نیست (`abmFileProvider` هنوز درحال بارگذاری یا
/// null است)، `graph: null` می‌ماند یعنی pass-through خالص — دقیقاً همان
/// رفتار قبل از این تغییر، بدون هیچ crash یا انتظاری برای UI.
final navigationPositionControllerProvider =
    Provider<NavigationPositionController>((ref) {
  final controller = NavigationPositionController(graph: null);
  controller.attach(ref.watch(vehiclePositionProvider.stream));
  ref.onDispose(controller.dispose);
  return controller;
});

/// خروجیِ نهاییِ pipeline: Raw GPS → Accuracy Check → Kalman Filter →
/// Map Matching → Navigation Position، به‌صورت ۶۰fps animated. این
/// جایگزینِ توصیه‌شده برای animatedVehiclePositionProvider است — همان
/// interpolation را دارد، به‌علاوه‌ی مرحله‌ی map matching.
final navigationPositionProvider = StreamProvider<VehiclePosition>((ref) {
  return ref.watch(navigationPositionControllerProvider).positionStream;
});

/// روشن/خاموش‌کننده‌ی فیلتر کالمن مشترک ۴بعدی. این فیلتر مسیر پیش‌فرض
/// ناوبری است تا موقعیت، سرعت و پیش‌بینی کوتاه‌مدت افت GPS یک منبع حقیقت
/// مشترک داشته باشند.
final jointKalmanEnabledProvider = StateProvider<bool>((ref) {
  return true;
});

final jointKalmanEnabledEffectProvider = Provider<void>((ref) {
  final enabled = ref.watch(jointKalmanEnabledProvider);
  ref.read(locationServiceProvider).setJointKalmanEnabled(enabled);
});

/// جریان زنده‌ی دیاگنوستیک فیلتر کالمن مشترک (خام در برابر هموارشده،
/// نویز حذف‌شده، مقادیر فعلی Q و R) برای نمایش در صفحه‌ی تنظیمات.
final jointKalmanDiagnosticsProvider =
    StreamProvider<JointKalmanDiagnostics>((ref) {
  return ref.watch(locationServiceProvider).jointKalmanDiagnostics;
});
