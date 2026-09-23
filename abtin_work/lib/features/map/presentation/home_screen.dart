import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as native_maplibre;
import 'package:go_router/go_router.dart';
import 'package:abtin_maps/core/geo/geo_types.dart';

import '../../../abtinmap/abm_models.dart';
import '../../routing/data/routing_provider.dart';
import '../../../core/deep_link/deep_link_service.dart';
import '../../../core/permissions/location_permission_flow.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/providers/app_settings_providers.dart';
import '../../../shared/providers/app_notice_provider.dart';
import '../../../shared/providers/map_style_providers.dart';
import '../../../shared/providers/abm_poi_visibility_providers.dart';
import '../../../shared/providers/abtinmap_providers.dart';
import '../../settings/presentation/settings_repository_provider.dart';
import '../../settings/presentation/appearance_settings_providers.dart'
    show
        appearanceSettingsProvider,
        AppearanceTab,
        mapTiltProvider,
        navigationCameraTiltProvider,
        vehicleViewAngleProvider,
        routeColorHexProvider,
        routeLineStyleProvider;
import '../../hud/presentation/hud_settings_providers.dart'
    show hudSettingsProvider;
import '../../../shared/widgets/bottom_nav.dart';
import '../../../shared/widgets/glass_notice.dart';
import '../../../shared/widgets/route_guidance_card.dart';
import '../../gps/data/location_service.dart';
import '../../gps/data/offline_road_snap_service.dart';
import '../../gps/presentation/gps_providers.dart';
import '../../offline_maps/presentation/offline_maps_providers.dart';
import 'online_map_view.dart';
import '../../routing/data/routing_service.dart';
import '../../routing/data/road_safety_service.dart';
import '../../routing/presentation/routing_providers.dart';
import '../../routing/presentation/road_alert_badge.dart';
import '../../routing/presentation/roundabout_dynamic.dart';
import '../../vehicle/presentation/modern_speedometer.dart';
import '../../vehicle/presentation/vehicle_provider.dart';
import '../../voice_settings/data/voice_pack_fa.dart';
import '../../voice_settings/presentation/tts_providers.dart';
import 'destination_provider.dart';
import '../../../shared/providers/share_service.dart';
import '../../../core/localization/app_localizations.dart';
import '../../saved_places/presentation/saved_places_providers.dart';
import '../../settings/data/settings_repository.dart';
import '../../system_info/presentation/unified_status_map_overlay.dart';
import '../../search/presentation/search_overlay.dart';
import '../../search/presentation/search_providers.dart';

Color _hexToColorOrDefault(String hex, String fallback) {
  String normalized(String value) => value.trim().replaceFirst('#', '');

  final candidate = normalized(hex);
  final fallbackValue = normalized(fallback);
  final value = candidate.length == 6 || candidate.length == 8
      ? candidate
      : fallbackValue;
  final argb = value.length == 6 ? 'FF$value' : value;
  final parsed = int.tryParse(argb, radix: 16);
  return Color(
    parsed ??
        int.parse(
          fallbackValue.length == 6 ? 'FF$fallbackValue' : fallbackValue,
          radix: 16,
        ),
  );
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _RouteSample {
  const _RouteSample(this.point, this.headingDeg, this.progressMeters);
  final LatLng point;
  final double headingDeg;
  final double progressMeters;
}

class _SegmentProjection {
  const _SegmentProjection({
    required this.t,
    required this.segmentMeters,
    required this.distanceMeters,
  });
  final double t;
  final double segmentMeters;
  final double distanceMeters;
}

class _RouteMatch {
  const _RouteMatch({required this.segmentIndex, required this.projection});
  final int segmentIndex;
  final _SegmentProjection projection;
  double get distanceMeters => projection.distanceMeters;
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  bool _cameraFollowsVehicle = true;
  int _gpsFocusRequest = 0;
  bool _didCenterOnFirstFix = false;
  bool _arrivalHandled = false;
  int _lastSpokenInstructionIndex = -1;

  /// مرحله‌های اعلام‌شده برای هر مانور (کلید: index*10 + stage) تا هر پیام
  /// دقیقاً یک‌بار و در فاصلهٔ درست گفته شود، نه زودتر و نه دیرتر.
  final Set<int> _spokenStages = <int>{};

  int _offRouteStrikeCount = 0;
  DateTime? _offRouteSince;
  bool _isRerouting = false;
  DateTime? _lastRerouteAt;
  VehiclePosition? _previousValidationPosition;
  DateTime? _previousValidationAt;
  double? _recentMovementBearingDeg;

  final RoadSafetyService _roadSafetyService = RoadSafetyService();
  RoadSafetySnapshot _roadSafety = const RoadSafetySnapshot();
  VehiclePosition? _normalSnappedVehiclePosition;
  DateTime? _normalSnapSourceAt;
  int _normalSnapRequest = 0;
  final OfflineRoadSnapService _offlineRoadSnapService =
      OfflineRoadSnapService();

  DateTime? _lastRoadSafetyUpdate;
  LatLng? _lastRoadSafetyCenter;
  bool _roadSafetyRequestInFlight = false;

  // هشدار جاده‌ای کوتاه‌مدت؛ مستقل از حالت Navigation. فقط آیکون تابلو
  // برای چند ثانیه روی نقشه می‌آید و بعد خودکار محو می‌شود.
  ({RouteAlert alert, double distanceM})? _transientRoadAlert;
  Timer? _transientRoadAlertTimer;
  final Map<String, DateTime> _shownRoadAlertKeys = <String, DateTime>{};
  static const double _movingAlertDistanceM = 300.0;
  static const double _movingAlertMinSpeedKmh = 5.0;

  bool _styleLoaded = false;
  bool _hudAutoOpening = false;
  bool _showMapRetry = false;
  Timer? _mapLoadTimeoutTimer;
  int _mapReloadKey = 0;

  // --- واچ‌داگِ «فیکس اول GPS» --------------------------------------------
  // باگ قبلی: وقتی سرویس مکان و مجوزها هر دو «ready» بودند اما به هر دلیلی
  // (داخل ساختمان، تراشه‌ی GPS کند، یا خطای بی‌صدای استریم که در
  // location_service.dart هم رفع شد) هیچ فیکسی هرگز نمی‌رسید، بنرِ بالای
  // نقشه چیزی نشان نمی‌داد (چون readiness == ready یعنی «مشکلی نیست»). از
  // نظر کاربر برنامه فقط برای همیشه ساکت می‌ماند — نه خطا، نه نشانه‌ای از
  // تلاش. این تایمر بعد از ۲۰ ثانیه انتظارِ بی‌نتیجه یک بنرِ راهنما نشان
  // می‌دهد و با ضربه، سرویس مکان را دوباره استارت می‌کند.
  bool _hasReceivedGpsFix = false;
  bool _showGpsStuckBanner = false;
  Timer? _gpsAcquireWatchdog;

  void _armGpsAcquireWatchdog() {
    if (_hasReceivedGpsFix || _gpsAcquireWatchdog != null) return;
    _gpsAcquireWatchdog = Timer(const Duration(seconds: 20), () {
      if (mounted && !_hasReceivedGpsFix) {
        setState(() => _showGpsStuckBanner = true);
      }
    });
  }

  void _onFirstGpsFixReceived() {
    if (_hasReceivedGpsFix) return;
    _hasReceivedGpsFix = true;
    _gpsAcquireWatchdog?.cancel();
    _transientRoadAlertTimer?.cancel();
    _gpsAcquireWatchdog = null;
    if (_showGpsStuckBanner && mounted) {
      setState(() => _showGpsStuckBanner = false);
    }
  }

  void _retryGpsAcquire() {
    
    setState(() => _showGpsStuckBanner = false);
    _gpsAcquireWatchdog?.cancel();
    _transientRoadAlertTimer?.cancel();
    _gpsAcquireWatchdog = null;
    ref.read(locationRepositoryProvider).start();
    _armGpsAcquireWatchdog();
  }

  Timer? _persistCameraDebounceTimer;

  /// آخرین موقعیت دوربینِ شناخته‌شده. وقتی resolvedMapStyleProvider عوض
  /// می‌شود (مثلاً درست بعد از اتمام دانلود نقشه: از استایل آنلاینِ فالبک به
  /// استایل آفلاینِ resolve‌شده)، چون این مقدار در key ویجت MapLibreMap هم
  /// هست، کل ویجت/کنترلر از نو ساخته می‌شود. بدون این فیلد،
  /// initialCameraPosition همیشه به‌طور ثابت روی تهران می‌افتاد — یعنی درست
  /// لحظه‌ی اتمام دانلود، دوربین از موقعیت واقعی کاربر می‌پرید تهران تا هر
  /// وقت GPS دوباره تصحیحش کند (و اگر _cameraFollowsVehicle در آن لحظه false
  /// بود، اصلاً تصحیح نمی‌شد).
  CameraPosition? _lastKnownCamera;
  final ValueNotifier<double> _mapBearingDegrees = ValueNotifier<double>(0);

  // نمای اولیه را روی کل ایران می‌گذاریم تا حتی قبل از GPS هم کاربر یک
  // نمای سراسریِ قابل‌فهم ببیند، نه یک نمای خیلی نزدیکِ ثابت روی تهران.
  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(32.5, 54.0),
    zoom: 5.1,
    tilt: 0,
    bearing: 0,
  );

  Future<void> _restoreSavedMapCamera() async {
    final repo = ref.read(settingsRepositoryProvider);
    final lat = await repo.getDouble(
      SettingsRepository.keyLastMapCenterLat,
      fallback: _initialCamera.target.latitude,
    );
    final lng = await repo.getDouble(
      SettingsRepository.keyLastMapCenterLng,
      fallback: _initialCamera.target.longitude,
    );
    final zoom = await repo.getDouble(
      SettingsRepository.keyLastMapZoom,
      fallback: _initialCamera.zoom,
    );
    final bearing = await repo.getDouble(
      SettingsRepository.keyLastMapBearing,
      fallback: _initialCamera.bearing,
    );
    final tilt = await repo.getDouble(
      SettingsRepository.keyLastMapTilt,
      fallback: _initialCamera.tilt,
    );
    final followsVehicle = await repo.getBool(
      SettingsRepository.keyLastMapFollowVehicle,
      fallback: true,
    );

    final restored = CameraPosition(
      target: LatLng(lat, lng),
      zoom: zoom.clamp(2.0, 16.0).toDouble(),
      bearing: bearing,
      tilt: tilt.clamp(0.0, 60.0).toDouble(),
    );

    _lastKnownCamera = restored;
    _mapBearingDegrees.value = restored.bearing;
    _cameraFollowsVehicle = followsVehicle;
    if (!followsVehicle) {
      _didCenterOnFirstFix = true;
    }
    if (mounted) setState(() {});
  }

  CameraPosition _currentLogicalCamera() => _lastKnownCamera ?? _initialCamera;

  void _persistMapCameraSoon() {
    _persistCameraDebounceTimer?.cancel();
    _persistCameraDebounceTimer = Timer(
      const Duration(milliseconds: 450),
      _persistMapCameraNow,
    );
  }

  Future<void> _persistMapCameraNow() async {
    final repo = ref.read(settingsRepositoryProvider);
    final camera = _currentLogicalCamera();
    await repo.setDouble(
      SettingsRepository.keyLastMapCenterLat,
      camera.target.latitude,
    );
    await repo.setDouble(
      SettingsRepository.keyLastMapCenterLng,
      camera.target.longitude,
    );
    await repo.setDouble(SettingsRepository.keyLastMapZoom, camera.zoom);
    await repo.setDouble(SettingsRepository.keyLastMapBearing, camera.bearing);
    await repo.setDouble(SettingsRepository.keyLastMapTilt, camera.tilt);
    await repo.setBool(
      SettingsRepository.keyLastMapFollowVehicle,
      _cameraFollowsVehicle,
    );
  }

  /// فقط فیکس زندهٔ pipeline GPS برای marker معتبر است. آخرین موقعیت
  /// ذخیره‌شده یا مرکز اولیه صرفاً برای دوربین‌اند؛ نمایش آن‌ها به‌عنوان خودرو
  /// علت مستقیم marker گمشده/شناور در مکان اشتباه بود.
  VehiclePosition? _resolveVehiclePosition(AsyncValue<VehiclePosition> live) {
    return live.valueOrNull;
  }

  // --- کش map-matching (نگاه کنید به _matchPositionToRoute) ---
  // geometry فقط برای تشخیصِ «مسیر عوض شده» (reroute) نگه داشته می‌شود؛
  // چون هر بار مسیرِ جدید محاسبه می‌شود یک List تازه است، مقایسه‌ی identical
  // کافی است — نیازی به مقایسه‌ی محتوا نیست.
  List<LatLng>? _routeMatchGeometry;
  List<double>? _routeMatchCumulativeM;
  int? _routeMatchLastSegment;
  double? _routeMatchLastProgressM;

  // کش «فاصله‌ی هر هشدار (دوربین/سرعت‌گیر/پلیس) از ابتدای مسیر» — یک‌بار
  // در ازای هر مسیر محاسبه می‌شود، نه هر فریم. نگاه کنید به
  // _upcomingAlerts.
  List<RouteAlert>? _routeAlertsSource;
  List<double>? _routeAlertsProgressM;

  // کش «فاصله‌ی هر مانورِ مسیر از ابتدای مسیر» (بر حسب متر، روی خودِ
  // پلی‌لاین، نه خطِ‌مستقیم). قبلاً فاصله‌ی خودرو تا مانورِ بعدی با
  // haversine مستقیم به مختصات همان مانور محاسبه می‌شد؛ چون مکانِ مانورِ
  // شماره‌ی صفر (در OSRM/آبتین‌مپ) همان نقطه‌ی مبدأ است، وقتی خودرو حرکت
  // می‌کرد فاصله‌ی مستقیم به آن نقطه به‌جای کم‌شدن زیاد می‌شد (عدد رومسیر
  // برعکس بالا می‌رفت). همچنین در پیچ‌ها، فاصله‌ی مستقیم مسیرِ واقعیِ جاده
  // را دنبال نمی‌کند. حالا از همان تصویرسازیِ روی پلی‌لاین که برای هشدارها
  // استفاده می‌شود بهره می‌بریم: فاصله‌ی هرمانور تا مانورِ بعدی = تفاضلِ
  // پیشرفتِ آن‌ها روی مسیر.
  List<RouteInstruction>? _routeInstructionsSource;
  List<double>? _routeInstructionsProgressM;

  /// حداکثر فاصله‌ای که هشدار در نوارِ بالای نقشه نمایش داده می‌شود.
  double get _alertDisplayRangeM =>
      ref.read(voiceFirstAlertDistanceProvider).clamp(50.0, 1000.0).toDouble();

  // LocationService افت کوتاه GPS را با کالمن مدیریت می‌کند. در شکاف طولانی
  // فقط روی هندسهٔ مسیر فعال جلو می‌رویم؛ پیش‌بینی آزاد در صفحه ممنوع است.
  Timer? _longTunnelWatchTimer;
  VehiclePosition? _lastNavigationSignal;
  DateTime? _lastNavigationSignalAt;
  VehiclePosition? _tunnelEstimatedPosition;
  DateTime? _tunnelEstimateStartedAt;
  DateTime? _lastTunnelEstimateAt;
  double _tunnelRouteProgressM = 0;
  bool _longTunnelEstimateExhausted = false;
  static const Duration _longTunnelSilenceBeforeStart = Duration(seconds: 5);
  static const Duration _maxLongTunnelEstimate = Duration(seconds: 25);
  static const double _minimumTunnelEstimateSpeedKmh = 8;

  void _startMapLoadWatchdog() {
    _mapLoadTimeoutTimer?.cancel();
    _showMapRetry = false;
    _mapLoadTimeoutTimer = Timer(const Duration(seconds: 20), () {
      if (mounted && !_styleLoaded) {
        setState(() => _showMapRetry = true);
      }
    });
  }

  void _retryMapLoad() {
    // Recreating the Flutter widget alone does not evict MapLibre's ambient
    // tile cache. Clear it first so a bad/empty cached tile cannot be replayed
    // forever on every retry. Offline regions are not removed by this call.
    unawaited(
      native_maplibre.clearAmbientCache().catchError((error) {
        
      }),
    );
    setState(() {
      _styleLoaded = false;
      _showMapRetry = false;
      _mapReloadKey++;
    });
    _startMapLoadWatchdog();
  }

  void _markMapStyleLoaded() {
    _mapLoadTimeoutTimer?.cancel();
    if (!mounted || (_styleLoaded && !_showMapRetry)) return;
    setState(() {
      _styleLoaded = true;
      _showMapRetry = false;
    });
  }

  void _onNativeCameraPosition(native_maplibre.CameraPosition camera) {
    final bearing = camera.bearing.isFinite ? camera.bearing % 360.0 : 0.0;
    _lastKnownCamera = CameraPosition(
      target: LatLng(camera.target.latitude, camera.target.longitude),
      zoom: camera.zoom,
      bearing: bearing,
      tilt: camera.tilt,
    );
    if ((_mapBearingDegrees.value - bearing).abs() > 0.05) {
      _mapBearingDegrees.value = bearing;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startMapLoadWatchdog();
    // Warm the actual selected GLB immediately. The navigation marker remains
    // a real 3D vehicle; this only moves the first asset read off the critical
    // route-start frame so the car can appear as soon as the MapLibre overlay
    // is mounted.
    final selectedVehicleIndex = ref
        .read(appearanceSettingsProvider)
        .vehicleModelIndex
        .clamp(0, vehicleModels.length - 1)
        .toInt();
    unawaited(warmUpVehicleModel(selectedVehicleIndex));
    _drivingModeSubscription = null;
    unawaited(_restoreSavedMapCamera());
    _longTunnelWatchTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _advanceLongTunnelEstimate(),
    );
  }

  StreamSubscription? _drivingModeSubscription;

  // باگ واقعیِ «لوکیشن اصلاً پیدا نمی‌شود»: locationReadinessProvider فقط
  // یک‌بار در build اول چک می‌شود و بعد فقط با
  // Geolocator.getServiceStatusStream() (که روی خیلی گوشی‌ها/OEMها وقتی
  // کاربر از داخل صفحه‌ی تنظیماتِ سیستم GPS/مجوز را روشن می‌کند و برمی‌گردد
  // به اپ، اصلاً trigger نمی‌شود) دوباره چک می‌شود. نتیجه: کاربر GPS یا
  // مجوز را در تنظیمات روشن می‌کند، به اپ برمی‌گردد، و LocationService.start()
  // هرگز صدا زده نمی‌شود — نقشه برای همیشه در حالت «waiting» بدون فیکس
  // می‌ماند. حالا با هر resume اپ (didChangeAppLifecycleState) وضعیت
  // readiness دوباره چک می‌شود، مستقل از این‌که سیستم‌عامل استریمِ سرویس
  // را trigger کرده باشد یا نه.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(locationLifecycleTickProvider.notifier).state++;
    }
  }

  void _maybeOpenHudAutomatically({
    required bool hudEnabled,
    required bool navigationActive,
  }) {
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape &&
        MediaQuery.of(context).size.width > MediaQuery.of(context).size.height;
    final shouldOpen = hudEnabled && navigationActive && landscape;
    if (!shouldOpen || _hudAutoOpening || !mounted) return;
    final location = GoRouterState.of(context).uri.path;
    if (location == '/hud-display') return;
    _hudAutoOpening = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await context.push('/hud-display');
      } finally {
        _hudAutoOpening = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final readiness = ref.watch(locationReadinessProvider);
    // هر چیزی که روی نقشه دیده می‌شود از یک جریان واحد و ۶۰fps می‌آید. پیش
    // از این، خودرو از GPS نرم‌شده اما دوربین از فیکس‌های گسسته حرکت می‌کرد؛
    // در نتیجه ماشین آرام می‌رفت ولی پس‌زمینه هر یک تا دو ثانیه می‌پرید.
    final vehiclePositionAsync = ref.watch(navigationPositionProvider);
    final destination = ref.watch(selectedDestinationProvider);
    final activeNav = ref.watch(activeNavigationProvider);
    final hudEnabled = ref.watch(hudSettingsProvider).enabled;
    _maybeOpenHudAutomatically(
      hudEnabled: hudEnabled,
      navigationActive: activeNav != null,
    );
    final searchActive = ref.watch(searchActiveProvider);
    final routeCandidatesAsync = ref.watch(calculateRoutesProvider);
    // وقتی مقصد/ناوبری لغو می‌شود، provider ممکن است برای یک فریم مقدار
    // قبلی را نگه دارد؛ overlay نباید در این فاصله خط مسیر را دوباره رسم کند.
    final routeCandidates =
        !searchActive && activeNav == null && destination != null
        ? (routeCandidatesAsync.valueOrNull ?? const <RouteInfo>[])
        : const <RouteInfo>[];
    final routeOptionsLoading =
        !searchActive &&
        activeNav == null &&
        destination != null &&
        routeCandidatesAsync.isLoading;
    final selectedRouteCandidateIndex = ref.watch(
      selectedRouteCandidateIndexProvider,
    );
    final selectedRouteIndex = routeCandidates.isEmpty
        ? 0
        : selectedRouteCandidateIndex.clamp(0, routeCandidates.length - 1);
    final liveVehiclePosition = _resolveVehiclePosition(vehiclePositionAsync);
    // Rendering must use the single 60fps navigation stream. The raw GPS
    // listener below is intentionally kept only for route progress; using its
    // value here reintroduced the exact 1Hz/2Hz position jumps we were trying
    // to eliminate. در حین ناوبری، همین جریانِ نرم روی هندسهٔ مسیر فعال
    // match می‌شود تا خودرو و پیکان دقیقاً روی همان مسیر و با جهت قطعهٔ جاده
    // نمایش داده شوند؛ نه فقط دوربین.
    // During navigation the animator is route-driven: its position is already
    // a 60fps sample on the active route. Do NOT map-match it against raw GPS
    // here; doing so would reintroduce the exact GPS-lag jump this pipeline is
    // designed to eliminate. The raw GPS is consumed separately below only
    // for validation/reroute.
    final snapIsFresh = _normalSnapSourceAt != null &&
        DateTime.now().difference(_normalSnapSourceAt!) < const Duration(seconds: 3);
    final baseVehiclePosition = activeNav == null
        ? (snapIsFresh ? (_normalSnappedVehiclePosition ?? liveVehiclePosition) : liveVehiclePosition)
        : liveVehiclePosition;
    // Both renderers consume this same position. During navigation project the
    // animated GPS sample onto the active route, so the car stays on the road
    // in MapLibre and in the offline canvas alike. Raw GPS remains available
    // to the off-route validator through _acceptNavigationSignal above.
    final matchedVehiclePosition =
        activeNav != null && baseVehiclePosition != null
        ? (_matchPositionToRoute(
                baseVehiclePosition,
                activeNav.route.geometry,
              ) ??
              baseVehiclePosition)
        : baseVehiclePosition;
    // Outside navigation the heading comes from the nearest ABM/OSM road
    // segment whenever available. During navigation the route geometry is the
    // stronger source of truth. GPS is only the fallback.
    final vehiclePosition = matchedVehiclePosition == null
        ? null
        : VehiclePosition(
            lat: matchedVehiclePosition.lat,
            lng: matchedVehiclePosition.lng,
            headingDeg: activeNav != null
                ? matchedVehiclePosition.headingDeg
                : (_roadSafety.roadHeadingDeg ??
                      matchedVehiclePosition.headingDeg),
            speedKmh: matchedVehiclePosition.speedKmh,
            accuracyM: matchedVehiclePosition.accuracyM,
            isEstimated: matchedVehiclePosition.isEstimated,
          );
    final canFollowVehicle = _cameraFollowsVehicle && vehiclePosition != null;
    final routingEngine = ref.watch(routingEngineProvider);
    final bool isDarkMap =
        ref.watch(mapStyleModeProvider) == MapStyleMode.night;
    final bool requestedOffline = routingEngine != RoutingEngine.online;
    final offlineFile = requestedOffline
        ? ref.watch(activeOfflineMapFileProvider).valueOrNull
        : null;
    final bool isOfflineMode = requestedOffline && offlineFile != null;
    // یک استایل واحد برای همهٔ حالت‌ها؛ مسیر فایلش با هر تغییرِ حالت/تم/پالت
    // عوض می‌شود (نام فایل = هش محتوا) و کلیدِ ویجت نقشه را هم عوض می‌کند.
    // نتیجهٔ مربوط به حالتِ دیگر (تا وقتی provider دوباره resolve نشده) نادیده
    // گرفته می‌شود تا نقشهٔ آنلاین با استایل آفلاین (و برعکس) ساخته نشود.
    final ResolvedMapStyle? resolvedStyleResult =
        ref.watch(resolvedMapStyleFileProvider).valueOrNull;
    final String? resolvedStyle =
        (resolvedStyleResult != null &&
            resolvedStyleResult.offline == isOfflineMode)
        ? resolvedStyleResult.path
        : null;
    _mapLoadTimeoutTimer?.cancel();
    final routeColorIndex = ref.watch(routeColorIndexProvider);
    final routeWidth = ref.watch(routeWidthProvider);
    final mapPerspective = ref.watch(mapPerspectiveProvider);
    final idleMapTilt = ref.watch(mapTiltProvider);
    final markerAppearance = ref.watch(appearanceSettingsProvider);
    final mapCameraTilt = activeNav != null
        ? ref.watch(navigationCameraTiltProvider).clamp(0.0, 60.0).toDouble()
        : (mapPerspective == MapPerspective.threeD
              ? idleMapTilt.clamp(0.0, 60.0).toDouble()
              : 0.0);
    final offlineMapPalette = ref.watch(currentOfflineMapPaletteProvider);
    ref.listen<AsyncValue<VehiclePosition>>(vehiclePositionProvider, (
      prev,
      next,
    ) {
      next.whenData((pos) {
        final navigation = ref.read(activeNavigationProvider);
        // Keep raw GPS as the validation signal. Do not feed it into the
        // route-match cache used by the 60fps visual progress, otherwise a
        // new GNSS sample can still move the guidance/alert progress abruptly.
        _acceptNavigationSignal(pos);
        _onFirstGpsFixReceived();
        if (ref.read(activeNavigationProvider) == null) {
          unawaited(_refreshNormalRoadSnap(pos));
        }
        // Road-safety warnings are independent of navigation. Refresh them
        // from ABM when offline and from OSM/Overpass when online, so the
        // same camera/speed-bump/speed-limit layer remains active before,
        // during and after route guidance.
        unawaited(_refreshRoadSafety(pos));
        if (!_didCenterOnFirstFix) {
          _didCenterOnFirstFix = true;
          if (mounted) setState(() => _gpsFocusRequest++);
        }
        if (navigation != null) {
          // Navigation UI/progress follows the same 60fps predicted position
          // as the marker. The raw GPS sample is passed separately only for
          // off-route validation, so a new GNSS fix cannot jump the guidance
          // card or alert distance.
          final animated =
              ref.read(navigationPositionProvider).valueOrNull ?? pos;
          _updateNavigationProgress(
            animated,
            navigation,
            gpsValidationPosition: pos,
          );
        }
      });
    });

    ref.listen<AsyncValue<LocationReadiness>>(locationReadinessProvider, (
      prev,
      next,
    ) {
      next.whenData((state) {
        if (state == LocationReadiness.ready) {
          _armGpsAcquireWatchdog();
        } else {
          // مجوز/سرویس دیگر ready نیست؛ بنر «هنوز فیکس نرسیده» معنایی
          // ندارد، چون بنر خطای مجوز/سرویس همین الان جایگزینش می‌شود.
          _gpsAcquireWatchdog?.cancel();
          _transientRoadAlertTimer?.cancel();
          _gpsAcquireWatchdog = null;
          if (_showGpsStuckBanner) {
            _showGpsStuckBanner = false;
          }
        }
      });
    });

    // وقتی مقصد جدیدی انتخاب می‌شود (از جستجو، مکان‌های ذخیره‌شده، و...)
    // دوربین باید به آن نقطه برود، وگرنه پین ممکن است کاملاً بیرون از
    // ناحیه‌ی دیدِ فعلی دوربین محاسبه شود و کاربر هیچ‌چیزی روی نقشه نبیند
    // (باگ قبلی: فقط دیپ‌لینک‌ها دوربین را جابه‌جا می‌کردند، نتیجه‌ی جستجو نه).
    ref.listen<SelectedDestination?>(selectedDestinationProvider, (prev, next) {
      if (next != null && prev?.point != next.point) {
        ref.read(selectedRouteCandidateIndexProvider.notifier).state = 0;
        setState(() => _cameraFollowsVehicle = false);
        _persistMapCameraSoon();
      }

      // «مسیریابی» از داخل نتایج سرچ (یا مکان ذخیره‌شده) با autoStart=true
      // می‌آید. خودِ انتخاب نتیجه نباید مسیریابی را شروع کند؛ فقط درخواست
      // صریحِ مسیریابی اینجا به _startNavigation سپرده می‌شود.
      if (next?.autoStart == true && prev?.autoStart != true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || ref.read(activeNavigationProvider) != null) return;
          final current = ref.read(selectedDestinationProvider);
          if (current?.point != next?.point || current?.autoStart != true)
            return;
          unawaited(_startNavigationWhenReady());
        });
      }
    });

    final canPopHome = destination == null && activeNav == null;

    return PopScope(
      canPop: canPopHome,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (activeNav != null) {
          _stopNavigation();
        } else if (destination != null) {
          ref.read(selectedDestinationProvider.notifier).state = null;
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.frameBackground(context),
        body: Stack(
          children: [
            Positioned.fill(
              child: resolvedStyle == null
                  ? Container(
                      color: isDarkMap
                          ? const Color(0xFF0b1014)
                          : const Color(0xFFcfe0e8),
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(),
                    )
                  : OnlineMapView(
                      // کلید به مسیر فایل استایل وابسته است. اسم فایل هش محتواست، پس
                      // هر تغییرِ شب/روز، پالت، فلش خیابان‌ها یا آنلاین/آفلاین =
                      // مسیر جدید = MapLibreMap از نو ساخته می‌شود؛ بدون نیاز به
                      // خروج و ورود مجدد به برنامه.
                      key: ValueKey(
                        isOfflineMode
                            ? 'offline-map-${offlineFile!.path}-$resolvedStyle'
                            : 'online-map-$resolvedStyle',
                      ),
                      vehiclePosition: vehiclePosition,
                      showCarModel:
                          markerAppearance.activeTab == AppearanceTab.car,
                      modelIndex: markerAppearance.vehicleModelIndex
                          .clamp(0, vehicleModels.length - 1)
                          .toInt(),
                      isDark: isDarkMap,
                      followVehicle: canFollowVehicle,
                      drivingMode: activeNav != null,
                      markerColor: markerAppearance.pinColor,
                      pinSizePercent: markerAppearance.pinSize,
                      carSizePercent: markerAppearance.carSizePercent,
                      pinShadowEnabled: markerAppearance.pinShadowEnabled,
                      cameraTiltDegrees: mapCameraTilt,
                      // زاویهٔ مدل باید از tilt واقعیِ نقشه پیروی کند؛ نه این‌که
                      // فقط وقتی «نمای 3D» در تنظیمات روشن است تغییر کند. بنابراین
                      // با 2D=0 و هر tilt دستی/ناوبری، مدل همان پرسپکتیو نقشه را می‌گیرد.
                      // اسلایدر نمای خودرو فقط می‌تواند زاویه را بیشتر کند، اما هیچ‌وقت
                      // اجازه ندارد مدل را از پرسپکتیؤ نقشه جدا کند.
                      carCameraAngleDegrees: math
                          .max(
                            ref
                                .watch(vehicleViewAngleProvider)
                                .clamp(0.0, 90.0),
                            (mapCameraTilt * 1.5).clamp(0.0, 90.0),
                          )
                          .toDouble(),
                      locationFocusRequest: _gpsFocusRequest,
                      palette: offlineMapPalette,
                      visiblePoiKlasses: ref.watch(abmPoiVisibilityProvider),
                      onPoiTap: (properties) {
                        if (!mounted) return;
                        final name = '${properties['name'] ?? properties['name_fa'] ?? properties['name_en'] ?? ''}'.trim();
                        final category = '${properties['category'] ?? properties['class'] ?? ''}'.trim();
                        final hours = '${properties['opening_hours'] ?? ''}'.trim();
                        showModalBottomSheet<void>(
                          context: context,
                          showDragHandle: true,
                          builder: (sheetContext) => SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name.isEmpty ? 'مکان' : name, style: Theme.of(sheetContext).textTheme.titleLarge),
                                  if (category.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(category),
                                  ],
                                  if (hours.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(hours),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                      // Offline uses the selected ABM as the data source;
                      // the bundled unified style remains the single visual style.
                      localStylePath: resolvedStyle,
                      abmFile: isOfflineMode ? offlineFile : null,
                      abmCountry: isOfflineMode
                          ? ref.read(activeOfflineMapIdProvider)
                          : null,
                      routeGeometry: activeNav?.route.geometry,
                      routeProgressMeters: activeNav == null
                          ? null
                          : (_routeMatchLastProgressM ??
                              _projectLatLngProgressMeters(
                                LatLng(vehiclePosition!.lat, vehiclePosition.lng),
                                activeNav.route.geometry,
                              )),
                      routeOverlays:
                          !searchActive &&
                              destination != null &&
                              activeNav == null &&
                              routeCandidates.isNotEmpty
                          ? [
                              for (
                                var index = 0;
                                index < routeCandidates.length && index < 3;
                                index++
                              )
                                OnlineRouteOverlay(
                                  geometry: routeCandidates[index].geometry,
                                  color: index == selectedRouteIndex
                                      ? const Color(0xFF2FE6C4)
                                      : const Color(
                                          0xFF99B4C1,
                                        ).withValues(alpha: 0.62),
                                  width: index == selectedRouteIndex
                                      ? routeWidth + 2
                                      : routeWidth,
                                ),
                            ]
                          : null,
                      routeColor: routeColorIndex < 0
                          ? _hexToColorOrDefault(
                              ref.watch(routeColorHexProvider),
                              kRouteColorHexes[0],
                            )
                          : Color(
                              int.parse(
                                'FF${kRouteColorHexes[routeColorIndex.clamp(0, kRouteColorHexes.length - 1)].substring(1)}',
                                radix: 16,
                              ),
                            ),
                      routeWidth: routeWidth,
                      destination: destination?.point,
                      onLongPress: (point) {
                        ref.read(selectedDestinationProvider.notifier).state =
                            SelectedDestination(point);
                        _takeManualCameraControl();
                      },
                      onRouteTap: (index) =>
                          ref
                                  .read(
                                    selectedRouteCandidateIndexProvider
                                        .notifier,
                                  )
                                  .state =
                              index,
                      onUserGestureStart: _takeManualCameraControl,
                      onCameraIdle: _persistMapCameraSoon,
                      onCameraPositionChanged: _onNativeCameraPosition,
                      onStyleLoaded: _markMapStyleLoaded,
                    ),
            ),

            // کارت یکپارچه آب‌وهوا، AQI، ساعت و باتری.
            const UnifiedStatusMapOverlay(),

            // این بنر برای هر دو حالتِ آنلاین/آفلاین معتبر است: چون هر دو از
            // همان OnlineMapView مشترکِ MapLibre استفاده می‌کنند، onStyleLoaded
            // برای هر دو _markMapStyleLoaded را صدا می‌زند.
            if (_showMapRetry && !_styleLoaded)
              Positioned(
                top:
                    MediaQuery.of(context).padding.top +
                    5 +
                    (activeNav != null
                        ? 140
                        : (destination != null
                              ? 108
                              : (readiness.valueOrNull != null &&
                                        readiness.valueOrNull !=
                                            LocationReadiness.ready
                                    ? 64
                                    : 12))),
                left: 24,
                right: 24,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.glassPanel(context),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(.12),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black45,
                            blurRadius: 16,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.cloud_off_rounded,
                            color: Colors.white70,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              AppStrings.literal('اتصال نقشه کند است…'),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: _retryMapLoad,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                gradient: AppColors.primaryGradient(context),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                AppStrings.literal('تلاش دوباره'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            Positioned(
              top:
                  MediaQuery.of(context).padding.top +
                  5 +
                  (activeNav != null ? 140 : (destination != null ? 108 : 12)),
              left: 24,
              right: 24,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, -0.3),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: readiness.when(
                  data: (state) => state != LocationReadiness.ready
                      ? _GpsWarningBanner(
                          key: ValueKey('gps-$state'),
                          state: state,
                        )
                      : (_showGpsStuckBanner
                            ? _GpsStuckBanner(
                                key: const ValueKey('gps-stuck'),
                                onRetry: _retryGpsAcquire,
                              )
                            : (activeNav != null &&
                                      _tunnelEstimatedPosition != null
                                  ? const _EstimatedLocationBanner(
                                      key: ValueKey('location-estimated'),
                                    )
                                  : const SizedBox.shrink(
                                      key: ValueKey('gps-ok'),
                                    ))),
                  loading: () =>
                      const SizedBox.shrink(key: ValueKey('gps-loading')),
                  error: (_, __) =>
                      const SizedBox.shrink(key: ValueKey('gps-error')),
                ),
              ),
            ),

            if (!searchActive && destination != null && activeNav == null)
              Positioned(
                // کارت راهنمای مسیر باید در بالاترین بخش ناحیهٔ نقشه قرار
                // بگیرد تا فضای عمودی بیشتری برای خود کارت داشته باشیم.
                // فاصلهٔ کوچک بعد از status bar جلوی برخورد با نوار سیستم را
                // می‌گیرد و دیگر کارت به بخش میانی نقشه هل داده نمی‌شود.
                top: MediaQuery.of(context).padding.top + 8.0,
                left: 16.0,
                right: 16.0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DestinationCard(
                      destination: destination,
                      onClear: () {
                        ref.read(selectedDestinationProvider.notifier).state =
                            null;
                        _clearRoute();
                      },
                      onStartNavigation: routeOptionsLoading
                          ? null
                          : () => unawaited(_startNavigationNow(
                                selectedRoute: routeCandidates.isEmpty
                                    ? null
                                    : routeCandidates[selectedRouteIndex],
                              )),
                    ),
                    if (routeCandidates.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _RouteChoiceStrip(
                        routes: routeCandidates.take(3).toList(growable: false),
                        selectedIndex: selectedRouteIndex,
                        onSelect: (index) {
                          ref
                              .read(selectedRouteCandidateIndexProvider.notifier)
                              .state = index;
                        },
                      ),
                    ],
                  ],
                ),
              ),

            // Compass & Floating Actions (Moved to Bottom Right)
            Positioned(
              bottom: 120,
              right: 16,
              child: Column(
                children: [
                  ValueListenableBuilder<double>(
                    valueListenable: _mapBearingDegrees,
                    builder: (context, bearing, _) =>
                        _Compass(mapBearingDeg: bearing),
                  ),
                  const SizedBox(height: 12),
                  _RoundIconButton(
                    icon: Icons.my_location_rounded,
                    onTap: () {
                      // درخواست تمرکز فقط به view واقعی MapLibre می‌رود؛ همان
                      // view زنجیرهٔ GPS زنده، آخرین موقعیت ذخیره‌شده و دوربین
                      // اولیه را مدیریت می‌کند.
                      setState(() {
                        _cameraFollowsVehicle = true;
                        _gpsFocusRequest++;
                      });
                      _persistMapCameraSoon();
                    },
                  ),
                ],
              ),
            ),

            // Speed Cluster (Speedometer + Speed Limit Sign) — ریسپانسیو
            // نسبت‌ها دقیقاً از index.html مرجع می‌آیند تا در هر سایز صفحه‌ای
            // یکسان به‌نظر برسند (به‌جای پیکسل ثابت که در صفحه‌های کوچک جابه‌جا می‌شد):
            //   .speed-cluster      { bottom:11.5%; left:2%; width:32%; height:15% }  (نسبت به صفحه)
            //   .speedometer        { left:0; bottom:0; width:66%; aspect-ratio:1/1 } (نسبت به کلاستر)
            //   .speed-limit-sign   { left:50%; bottom:35%; width:44%; aspect-ratio:1/1 } (نسبت به کلاستر)
            //
            // چرا Consumer جدا: قبلاً currentSpeed از vehiclePositionAsync ای
            // می‌آمد که در بالای build() این صفحه (۳۰۰۰+ خط) با ref.watch
            // خوانده شده بود. یعنی هر تیکِ ۶۰fps انیماتورِ موقعیت، کل ساب‌تریِ
            // صفحه (نقشه، دوربین، لایه‌های POI و...) را از نو می‌ساخت — کاری
            // که فریم را عقب می‌انداخت و نتیجه‌اش دقیقاً همان چیزی بود که
            // گزارش شد: عدد سرعت هر ۱-۲ ثانیه یک‌باره می‌پرید، نه هر ۱۶ms
            // نرم. با یک Consumer مجزا، فقط همین ویجت کوچک روی هر فیکسِ
            // انیماتور rebuild می‌شود و بقیه‌ی صفحه دست‌نخورده می‌ماند.
            Builder(
              builder: (context) {
                final screenSize = MediaQuery.of(context).size;
                final clusterWidth = screenSize.width * 0.32;
                final clusterHeight = screenSize.height * 0.15;
                final clusterBottom = screenSize.height * 0.115;
                final clusterLeft = screenSize.width * 0.02;
                final speedometerSize = clusterWidth * 0.66;
                final signSize = clusterWidth * 0.44;

                return Positioned(
                  bottom: clusterBottom,
                  left: clusterLeft,
                  width: clusterWidth,
                  height: clusterHeight,
                  child: Consumer(
                    builder: (context, ref, _) {
                      final currentSpeed =
                          _tunnelEstimatedPosition?.speedKmh ??
                          ref
                              .watch(navigationPositionProvider)
                              .valueOrNull
                              ?.speedKmh ??
                          0;
                      final speedLimit =
                          activeNav?.currentInstruction.speedLimit ??
                          _roadSafety.speedLimitKmh;
                      // فقط وقتی سرعت فعلی نزدیک/بالاترِ محدودیت است تابلو نمایش
                      // داده می‌شود؛ همیشه نمایش‌دادنش وقتی فاصله‌ی زیادی با
                      // محدودیت هست بی‌فایده و مزاحم است.
                      final showSpeedLimit =
                          speedLimit != null && currentSpeed >= speedLimit - 10;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // تابلوی محدودیت سرعت زیرِ سرعت‌سنج قرار می‌گیرد (z-index
                          // پایین‌تر)؛ به همین دلیل باید قبل از سرعت‌سنج در Stack
                          // اضافه شود.
                          if (showSpeedLimit)
                            Positioned(
                              left: clusterWidth * 0.50,
                              bottom: clusterHeight * 0.35,
                              width: signSize,
                              height: signSize,
                              child: _SpeedLimitSign(
                                value: speedLimit.toString(),
                              ),
                            ),
                          Positioned(
                            left: 0,
                            bottom: 0,
                            width: speedometerSize,
                            height: speedometerSize,
                            child: ModernSpeedometer(speedKmh: currentSpeed),
                          ),
                        ],
                      );
                    },
                  ),
                );
              },
            ),

            const BottomNav(currentPage: NavKey.home, isHomePage: true),

            // لایهٔ جستجو: با لمس دکمهٔ سرچ در نوار پایین باز می‌شود؛ روی
            // همه‌چیز (نقشه، بنرها، BottomNav) قرار می‌گیرد. AnimatedSwitcher
            // برای نمایش/پنهان‌شدن نرم استفاده شده.
            if (ref.watch(searchActiveProvider))
              const Positioned.fill(child: SearchOverlay()),

            // کارت مسیر دست‌نخورده است؛ هشدارها فقط در زیر همان کارت،
            // به‌صورت یک زنجیرهٔ فشرده و بدون فاصله نمایش داده می‌شوند.
            if (activeNav != null && !searchActive)
              Positioned(
                // کارت راهنمای مسیر باید در بالاترین بخش ناحیهٔ نقشه قرار
                // بگیرد تا فضای عمودی بیشتری برای خود کارت داشته باشیم.
                // فاصلهٔ کوچک بعد از status bar جلوی برخورد با نوار سیستم را
                // می‌گیرد و دیگر کارت به بخش میانی نقشه هل داده نمی‌شود.
                top: MediaQuery.of(context).padding.top + 8.0,
                left: 16.0,
                right: 16.0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ActiveNavigationCard(
                      navigation: activeNav,
                      onClose: () => _stopNavigation(),
                    ),
                    Builder(
                      builder: (context) {
                        final alerts = _displayRoadAlerts(activeNav);
                        if (alerts.isEmpty) return const SizedBox.shrink();
                        final appearance = ref.watch(
                          appearanceSettingsProvider,
                        );
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: RoadAlertStack(
                              alerts: [for (final item in alerts) item.alert],
                              sizePercent: appearance.routeAlertSizePercent,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _mapLoadTimeoutTimer?.cancel();
    unawaited(_offlineRoadSnapService.dispose());
    _persistCameraDebounceTimer?.cancel();
    _longTunnelWatchTimer?.cancel();
    _drivingModeSubscription?.cancel();
    _gpsAcquireWatchdog?.cancel();
    _transientRoadAlertTimer?.cancel();
    _mapBearingDegrees.dispose();
    _roadSafetyService.dispose();
    super.dispose();
  }

  void _showGlassNotice(
    String message, {
    required IconData icon,
    required List<Color> colors,
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!mounted) return;
    final level = colors.contains(Colors.red)
        ? AppNoticeLevel.error
        : colors.contains(Colors.orange)
        ? AppNoticeLevel.warning
        : AppNoticeLevel.info;
    unawaited(
      ref
          .read(appNoticeProvider.notifier)
          .show(
            title: AppStrings.literal('آبتین مپس'),
            message: message,
            level: level,
          ),
    );
    showGlassNotice(
      context,
      message,
      icon: icon,
      colors: colors,
      duration: duration,
    );
  }

  Future<void> _startNavigationWhenReady() async {
    // Deep-link may arrive a few milliseconds before the first GPS sample.
    // Do not lose the navigation request just because the first frame has no
    // position yet; wait briefly for the normal navigation position stream.
    if (ref.read(activeNavigationProvider) != null) return;
    if (ref.read(vehiclePositionProvider).value == null) {
      final completer = Completer<void>();
      late final ProviderSubscription<AsyncValue<VehiclePosition>> sub;
      sub = ref.listenManual(vehiclePositionProvider, (prev, next) {
        if (next.value != null && !completer.isCompleted) {
          completer.complete();
        }
      });
      try {
        await completer.future.timeout(const Duration(seconds: 8));
      } catch (_) {
        // Let _startNavigation show/handle the normal GPS-unavailable state.
      } finally {
        sub.close();
      }
    }
    if (!mounted || ref.read(activeNavigationProvider) != null) return;
    final destination = ref.read(selectedDestinationProvider);
    if (destination?.autoStart != true) return;
    unawaited(_startNavigationNow());
  }

  /// مسیر فعال را در لحظهٔ شروع/تغییر مسیر روی آخرین موقعیت زندهٔ خودرو
  /// دوباره مبناگذاری می‌کند. اگر محاسبهٔ مسیر چند ثانیه طول کشیده باشد،
  /// origin اولیه می‌تواند پشت خودرو بماند؛ نگه‌داشتن آن بخشِ قدیمی باعث می‌شود
  /// «نقطهٔ شروع مسیر» از نشانگر فاصله داشته باشد. این تابع فقط بخشِ طی‌شدهٔ
  /// polyline را حذف می‌کند و یک نقطهٔ projection دقیق در محل فعلی خودرو
  /// می‌گذارد؛ مسیر آینده و ترتیب خیابان‌ها دست‌نخورده می‌ماند.
  RouteInfo _rebaseRouteToVehicle(RouteInfo route, VehiclePosition vehicle) {
    final geometry = route.geometry;
    if (geometry.length < 2) return route;

    final match = _bestSegmentMatch(vehicle, geometry, 0, geometry.length - 2);
    if (match == null || match.distanceMeters > 80.0) return route;

    final segment = geometry[match.segmentIndex];
    final next = geometry[match.segmentIndex + 1];
    final t = match.projection.t.clamp(0.0, 1.0).toDouble();
    final projected = LatLng(
      segment.latitude + (next.latitude - segment.latitude) * t,
      segment.longitude + (next.longitude - segment.longitude) * t,
    );

    final rebased = <LatLng>[projected];
    for (var i = match.segmentIndex + 1; i < geometry.length; i++) {
      final point = geometry[i];
      if (_calculateDistance(rebased.last, point) > 0.05) {
        rebased.add(point);
      }
    }
    if (rebased.length < 2) return route;

    final originalDistance = math.max(route.distanceKm, 0.001);
    final remainingDistanceKm = _routeGeometryDistanceKm(rebased);
    final ratio = (remainingDistanceKm / originalDistance).clamp(0.0, 1.0);

    // Instructions keep their original geographic locations. Their progress
    // is recalculated against this rebased geometry by the navigation layer.
    return RouteInfo(
      geometry: List<LatLng>.unmodifiable(rebased),
      distanceKm: remainingDistanceKm,
      durationMin: route.durationMin * ratio,
      instructions: route.instructions,
      alerts: route.alerts,
    );
  }

  double _routeGeometryDistanceKm(List<LatLng> geometry) {
    var meters = 0.0;
    for (var i = 1; i < geometry.length; i++) {
      meters += _calculateDistance(geometry[i - 1], geometry[i]);
    }
    return meters / 1000.0;
  }

  Future<void> _startNavigationNow({RouteInfo? selectedRoute}) async {
    final destination = ref.read(selectedDestinationProvider);
    final vehiclePosition =
        ref.read(vehiclePositionProvider).value ??
        ref.read(navigationPositionProvider).valueOrNull;

    if (destination == null || vehiclePosition == null) return;

    final origin = LatLng(vehiclePosition.lat, vehiclePosition.lng);
    // اگر مقصد (مثلاً یک مکان ذخیره‌شده) عملاً همان نقطه‌ی فعلی GPS باشد،
    // مسیریابی یک مسیر صفر-متری بی‌معنی برمی‌گرداند. به‌جای تلاش برای
    // «مسیریابی» به همان‌جا، پیام ساده نشان می‌دهیم.
    if (AbmTileMath.haversineMeters(
          AbmPoint(origin.longitude, origin.latitude),
          AbmPoint(destination.point.longitude, destination.point.latitude),
        ) <
        20) {
      _showGlassNotice(
        AppStrings.literal('شما همین الان در مقصد هستید.'),
        icon: Icons.flag_rounded,
        colors: const [Colors.teal, Colors.green],
      );
      return;
    }

    _arrivalHandled = false;
    _offRouteStrikeCount = 0;
    _offRouteSince = null;
    _previousValidationPosition = null;
    _previousValidationAt = null;
    _recentMovementBearingDeg = null;
    _spokenStages.clear();

    try {
      var route =
          selectedRoute ?? await _computeRoute(origin, destination.point);
      if (!mounted) return;

      // Route calculation is asynchronous. The GPS position captured before
      // _computeRoute() may already be hundreds of metres old when the route
      // returns. Re-read the live position before attaching the animation
      // track; otherwise the marker/camera start at the old projection on the
      // polyline and visibly trail the real vehicle.
      var livePosition =
          ref.read(vehiclePositionProvider).value ??
          ref.read(navigationPositionProvider).valueOrNull ??
          vehiclePosition;

      // If the driver moved materially while the route was being calculated,
      // rebuild the route from the current position so the new polyline itself
      // starts at (or very near) the vehicle instead of relying on a stale
      // origin. Do not redo a user-selected route, because its geometry is
      // authoritative.
      if (selectedRoute == null &&
          livePosition != null &&
          AbmTileMath.haversineMeters(
                AbmPoint(origin.longitude, origin.latitude),
                AbmPoint(livePosition.lng, livePosition.lat),
              ) >
              30) {
        route = await _computeRoute(
          LatLng(livePosition.lat, livePosition.lng),
          destination.point,
        );
        if (!mounted) return;
      }

      // Rebase the visual/active route to the newest live vehicle position.
      // This removes the already-travelled tail of the calculated polyline and
      // guarantees that route[0], vehicle and follow-camera all share the same
      // geographic anchor at navigation start.
      route = _rebaseRouteToVehicle(route, livePosition);
      await _drawRoute(route.geometry);

      // _drawRoute() can also be asynchronous. Take one final live sample so
      // the animation anchor is the driver's current position, not a sample
      // from before route calculation/rendering.
      livePosition =
          ref.read(vehiclePositionProvider).value ??
          ref.read(navigationPositionProvider).valueOrNull ??
          livePosition;
      route = _rebaseRouteToVehicle(route, livePosition);

      ref
          .read(activeNavigationProvider.notifier)
          .setNavigation(
            ActiveNavigation(
              route: route,
              state: NavigationState.navigating,
              remainingDistanceKm: route.distanceKm,
            ),
          );

      ref
          .read(navigationPositionControllerProvider)
          .setActiveRoute(route.geometry, anchor: livePosition);

      if (route.instructions.isNotEmpty && ref.read(ttEnabledProvider)) {
        _lastSpokenInstructionIndex = 0;
        // پیام شروع، خودِ مرحلهٔ دور اولین مانور است؛ دوباره تکرار نشود.
        _spokenStages.addAll(const [0, 1]);
        final voice = ref.read(ttsServiceProvider)
          ..setVolume(ref.read(ttsVolumeProvider))
          ..setPlaybackRate(ref.read(ttsRateProvider));
        voice.playCue('route_found');
      }

      // فعال کردن follow mode: دوربین پیکان را دنبال می‌کند
      setState(() => _cameraFollowsVehicle = true);

      // فعال‌کردن حالت رانندگی
      ref.read(drivingModeProvider.notifier).state = true;
    } catch (e) {
      _showGlassNotice(
        AppStrings.literal('خطا در محاسبه مسیر: $e'),
        icon: Icons.error_outline_rounded,
        colors: [Colors.red, Colors.orange],
      );
    }
  }

  /// منتظرِ اولین سرعتِ محسوسِ خودرو می‌ماند (تشخیصِ شروعِ حرکتِ واقعی) تا
  /// ناوبری همان لحظه، بدونِ تأخیرِ ثابت، آغاز شود. اگر جریانِ موقعیت پیش
  /// از رسیدن به آستانه قطع/خطا شود، بی‌درنگ ادامه می‌دهد.
  static const double _movementStartSpeedThresholdKmh = 3;

  Future<void> _waitForMovementStart() async {
    final immediate = ref.read(navigationPositionProvider).value;
    if ((immediate?.speedKmh ?? 0) >= _movementStartSpeedThresholdKmh) return;

    final completer = Completer<void>();
    late final ProviderSubscription<AsyncValue<VehiclePosition>> sub;
    sub = ref.listenManual(navigationPositionProvider, (prev, next) {
      final speed = next.value?.speedKmh ?? 0;
      if (speed >= _movementStartSpeedThresholdKmh && !completer.isCompleted) {
        completer.complete();
      }
    });
    try {
      await completer.future;
    } finally {
      sub.close();
    }
  }

  Future<RouteInfo> _computeRoute(LatLng origin, LatLng destination) async {
    // فقط موتور انتخاب‌شده‌ی فعلی اجرا می‌شود. در حالت آفلاین، هیچ fallback
    // آنلاینی مجاز نیست؛ اگر مسیر معتبر روی گراف واقعی .abm پیدا نشود، همان
    // خطای واقعی به کاربر نشان داده می‌شود.
    final service = ref.read(routingServiceProvider);
    final route = await service.calculateRoute(
      origin: origin,
      destination: destination,
      avoidUnpavedRoads: ref.read(appearanceSettingsProvider).avoidUnpavedRoads,
      avoidTolls: ref.read(appearanceSettingsProvider).avoidTolls,
    );
    if (route != null) return route;
    throw Exception(
      service.lastError ??
          AppStrings.literal('مسیری روی شبکهٔ واقعی جاده‌ها پیدا نشد'),
    );
  }

  void _rerouteOffPath(
    double deviationMeters, {
    VehiclePosition? gpsPosition,
  }) async {
    if (_isRerouting) return;
    _isRerouting = true;
    _lastRerouteAt = DateTime.now();

    if (gpsPosition != null) {
      // Stop the old route clock immediately. The marker must follow the road
      // the driver is actually on while the replacement route is computed.
      ref
          .read(navigationPositionControllerProvider)
          .adoptGpsAnchor(gpsPosition);
    }

    final destination = ref.read(selectedDestinationProvider);
    // Once the driver has actually left the planned road, the raw validated
    // GPS position is the correct reroute origin. The old route-driven marker
    // can be tens of metres ahead on the planned turn, so using it here would
    // reproduce the exact delayed/deceptive behaviour seen in the recording.
    final vehiclePosition =
        gpsPosition ??
        ref.read(navigationPositionProvider).valueOrNull ??
        ref.read(vehiclePositionProvider).value;

    if (destination == null || vehiclePosition == null) {
      _isRerouting = false;
      return;
    }

    if (ref.read(alertsVoiceEnabledProvider)) {
      final voice = ref.read(ttsServiceProvider)
        ..setVolume(ref.read(ttsVolumeProvider))
        ..setPlaybackRate(ref.read(ttsRateProvider));
      voice.playCue('off_route');
    }
    _showGlassNotice(
      AppStrings.literal('از مسیر خارج شدید؛ مسیر جدید در حال محاسبه است'),
      icon: Icons.alt_route_rounded,
      colors: const [Color(0xFFF59E0B), Color(0xFFEF4444)],
      duration: const Duration(seconds: 4),
    );

    try {
      final origin = LatLng(vehiclePosition.lat, vehiclePosition.lng);
      var route = await _computeRoute(origin, destination.point);

      if (!mounted || ref.read(activeNavigationProvider) == null) return;

      // The driver can move while the replacement route is being calculated.
      // Use the newest validated position as the anchor and, when the movement
      // is material, calculate the replacement route from that newer origin.
      var livePosition =
          ref.read(vehiclePositionProvider).value ??
          ref.read(navigationPositionProvider).valueOrNull ??
          vehiclePosition;
      if (livePosition != null &&
          AbmTileMath.haversineMeters(
                AbmPoint(origin.longitude, origin.latitude),
                AbmPoint(livePosition.lng, livePosition.lat),
              ) >
              30) {
        route = await _computeRoute(
          LatLng(livePosition.lat, livePosition.lng),
          destination.point,
        );
        if (!mounted || ref.read(activeNavigationProvider) == null) return;
      }

      route = _rebaseRouteToVehicle(route, livePosition);
      await _drawRoute(route.geometry);

      livePosition =
          ref.read(vehiclePositionProvider).value ??
          ref.read(navigationPositionProvider).valueOrNull ??
          livePosition;
      route = _rebaseRouteToVehicle(route, livePosition);

      ref
          .read(activeNavigationProvider.notifier)
          .setNavigation(
            ActiveNavigation(
              route: route,
              state: NavigationState.navigating,
              remainingDistanceKm: route.distanceKm,
            ),
          );

      // Replace the animation track immediately with the new route. The
      // current rendered position is used as the anchor so the car never
      // snaps back to the delayed GPS fix while rerouting.
      ref
          .read(navigationPositionControllerProvider)
          .setActiveRoute(route.geometry, anchor: livePosition);

      _showGlassNotice(
        AppStrings.literal('مسیر جدید آماده است'),
        icon: Icons.route_rounded,
        colors: const [Color(0xFF8B5CF6), Color(0xFF3B82F6)],
      );

      _arrivalHandled = false;
      _lastSpokenInstructionIndex = -1;
      _spokenStages.clear();
      if (route.instructions.isNotEmpty && ref.read(ttEnabledProvider)) {
        _lastSpokenInstructionIndex = 0;
        // پیام شروع، خودِ مرحلهٔ دور اولین مانور است؛ دوباره تکرار نشود.
        _spokenStages.addAll(const [0, 1]);
        final voice = ref.read(ttsServiceProvider)
          ..setVolume(ref.read(ttsVolumeProvider))
          ..setPlaybackRate(ref.read(ttsRateProvider));
        voice.playCue('recalculating_route');
      }
    } finally {
      _isRerouting = false;
    }
  }

  /// مسیر را فقط برای لایهٔ مسیر نرم می‌کند؛ هندسهٔ خودِ نقشه و خیابان‌ها
  /// دست‌نخورده می‌مانند. فقط رأس‌هایی که واقعاً بیانگر یک قوسِ ملایمِ خیابان
  /// هستند smooth می‌شوند (زاویهٔ تغییر جهت کوچک)؛ رأس‌های تیز — تقاطع‌ها،
  /// گوشه‌های میدان، پیچ‌های واقعی خیابان — دست‌نخورده و کاملاً گوشه‌دار
  /// می‌مانند تا شکلِ رسم‌شده دقیقاً منطبق با دیتای واقعیِ نقشه بماند.
  List<LatLng> _smoothRouteGeometry(List<LatLng> geometry) {
    if (geometry.length < 3) return geometry;

    // فقط بندهای کوتاه (نمایانگر یک نقطهٔ داخلیِ زنجیرهٔ ادغام‌شده، نه یک
    // خیابان مجزا) و با زاویهٔ بازِ کافی (پیچِ ملایم، نه تقاطع/گوشهٔ تیز)
    // کاندید smoothing هستند.
    const maxSegmentMeters = 35.0; // طول بند برای واجد شرایط بودن
    const minAngleDegForSmoothing = 150.0; // زاویهٔ بازتر یعنی پیچ ملایم‌تر
    const samples = 6;

    double distMeters(LatLng a, LatLng b) {
      const R = 6371000.0;
      final dLat = (b.latitude - a.latitude) * math.pi / 180.0;
      final dLon = (b.longitude - a.longitude) * math.pi / 180.0;
      final lat1 = a.latitude * math.pi / 180.0;
      final lat2 = b.latitude * math.pi / 180.0;
      final h =
          math.sin(dLat / 2) * math.sin(dLat / 2) +
          math.cos(lat1) *
              math.cos(lat2) *
              math.sin(dLon / 2) *
              math.sin(dLon / 2);
      return 2 * R * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    }

    // زاویهٔ داخلیِ رأس b بین a→b→c؛ 180 یعنی کاملاً مستقیم، هرچه کمتر یعنی تیزتر.
    double interiorAngleDeg(LatLng a, LatLng b, LatLng c) {
      final v1x = a.longitude - b.longitude;
      final v1y = a.latitude - b.latitude;
      final v2x = c.longitude - b.longitude;
      final v2y = c.latitude - b.latitude;
      final dot = v1x * v2x + v1y * v2y;
      final mag1 = math.sqrt(v1x * v1x + v1y * v1y);
      final mag2 = math.sqrt(v2x * v2x + v2y * v2y);
      if (mag1 == 0 || mag2 == 0) return 180.0;
      final cosA = (dot / (mag1 * mag2)).clamp(-1.0, 1.0);
      return math.acos(cosA) * 180.0 / math.pi;
    }

    LatLng mid(LatLng a, LatLng b) => LatLng(
      (a.latitude + b.latitude) / 2.0,
      (a.longitude + b.longitude) / 2.0,
    );

    final out = <LatLng>[geometry.first];

    for (var i = 1; i < geometry.length - 1; i++) {
      final prev = geometry[i - 1];
      final control = geometry[i];
      final next = geometry[i + 1];

      final segIn = distMeters(prev, control);
      final segOut = distMeters(control, next);
      final angle = interiorAngleDeg(prev, control, next);

      final eligible =
          segIn <= maxSegmentMeters &&
          segOut <= maxSegmentMeters &&
          angle >= minAngleDegForSmoothing;

      if (!eligible) {
        // رأس تیز/تقاطع: دقیقاً همان نقطهٔ واقعیِ نقشه را نگه می‌داریم.
        out.add(control);
        continue;
      }

      final start = mid(prev, control);
      final end = mid(control, next);

      for (var j = 1; j <= samples; j++) {
        final t = j / samples;
        final mt = 1.0 - t;
        out.add(
          LatLng(
            mt * mt * start.latitude +
                2 * mt * t * control.latitude +
                t * t * end.latitude,
            mt * mt * start.longitude +
                2 * mt * t * control.longitude +
                t * t * end.longitude,
          ),
        );
      }
    }

    out.add(geometry.last);
    return out;
  }

  Future<void> _drawRoute(List<LatLng> geometry) async {
    // خط مسیر روی Canvas آفلاین توسط routeGeometry رسم می‌شود. MapLibre و
    // GeoJSON source آنلاین از این build حذف شده‌اند.
  }

  Map<String, dynamic> _lineStringFrom(List<LatLng> geometry) => {
    'type': 'FeatureCollection',
    'features': [
      {
        'type': 'Feature',
        'properties': <String, dynamic>{},
        'geometry': {
          'type': 'LineString',
          'coordinates': geometry
              .map((p) => [p.longitude, p.latitude])
              .toList(),
        },
      },
    ],
  };

  Future<void> _clearRoute() async {
    // فقط تغییر مقصد کافی نیست؛ شاخص route انتخاب‌شده و خود widget نقشه
    // نیز باید در همان frame به وضعیت بدون مسیر برگردند.
    ref.read(selectedRouteCandidateIndexProvider.notifier).state = 0;
    if (ref.read(selectedDestinationProvider) != null) {
      ref.read(selectedDestinationProvider.notifier).state = null;
    }
    if (mounted) setState(() {});
  }

  void _takeManualCameraControl() {
    if (!_cameraFollowsVehicle) return;
    setState(() => _cameraFollowsVehicle = false);
    _persistMapCameraSoon();
    // دوربین دیگر پیکان را دنبال نمی‌کند تا کاربر دوباره روی دکمه my_location بزند
  }

  void _acceptNavigationSignal(VehiclePosition pos) {
    final now = DateTime.now();
    final previous = _previousValidationPosition;
    _lastNavigationSignal = pos;
    _lastNavigationSignalAt = now;
    _longTunnelEstimateExhausted = false;
    final nav = ref.read(activeNavigationProvider);
    if (nav != null) {
      _tunnelRouteProgressM = _projectRouteProgressMeters(
        pos,
        nav.route.geometry,
      );
    }
    if (_tunnelEstimatedPosition != null) {
      _clearLongTunnelEstimate(notify: true);
      
    }
  }

  void _advanceLongTunnelEstimate() {
    if (!mounted) return;
    final nav = ref.read(activeNavigationProvider);
    final last = _lastNavigationSignal;
    final lastAt = _lastNavigationSignalAt;
    if (nav == null ||
        last == null ||
        lastAt == null ||
        nav.route.geometry.length < 2 ||
        last.isEstimated ||
        last.speedKmh < _minimumTunnelEstimateSpeedKmh) {
      _clearLongTunnelEstimate();
      return;
    }

    final now = DateTime.now();
    if (_longTunnelEstimateExhausted) return;
    final silence = now.difference(lastAt);
    if (silence < _longTunnelSilenceBeforeStart) return;

    _tunnelEstimateStartedAt ??= now;
    final estimatedFor = now.difference(_tunnelEstimateStartedAt!);
    if (estimatedFor > _maxLongTunnelEstimate) {
      if (_tunnelEstimatedPosition != null) {
        
        // نگه‌داشتن آخرین نقطهٔ ساختگی باعث می‌شد banner «موقعیت تخمینی»
        // تا بازگشت GPS برای همیشه دیده شود. پس از سقف مجاز، marker به
        // جریان عادی موقعیت برمی‌گردد و فقط از ساخت estimate بعدی جلوگیری
        // می‌کنیم.
        _clearLongTunnelEstimate();
        _longTunnelEstimateExhausted = true;
        if (mounted) setState(() {});
      }
      return;
    }

    final previousAt = _lastTunnelEstimateAt ?? lastAt;
    final deltaSeconds = now.difference(previousAt).inMilliseconds / 1000.0;
    if (deltaSeconds <= 0) return;
    _lastTunnelEstimateAt = now;

    // پس از بیست ثانیه، سرعت را به‌آرامی کم می‌کنیم. بدون odometer/IMU
    // کالیبره‌شده نباید تا انتهای تونل با سرعت آخرین GPS کورکورانه برویم.
    final seconds = estimatedFor.inMilliseconds / 1000.0;
    final speedFactor =
        (seconds <= 20
                ? 1.0
                : (1.0 - ((seconds - 20) / 100) * 0.7).clamp(0.3, 1.0))
            .toDouble();
    final speedKmh = (last.speedKmh * speedFactor).clamp(0.0, 130.0).toDouble();
    final nextProgress =
        _tunnelRouteProgressM + (speedKmh / 3.6) * deltaSeconds;
    final sample = _routeSampleAtMeters(nav.route.geometry, nextProgress);
    if (sample == null) return;
    _tunnelRouteProgressM = sample.progressMeters;
    final estimated = VehiclePosition(
      lat: sample.point.latitude,
      lng: sample.point.longitude,
      headingDeg: sample.headingDeg,
      speedKmh: speedKmh,
      // به UI و map matching نشان می‌دهیم که با گذر زمان اطمینان کم می‌شود.
      accuracyM: (last.accuracyM + seconds * 5).clamp(8.0, 500.0).toDouble(),
      isEstimated: true,
    );

    final firstEstimate = _tunnelEstimatedPosition == null;
    _tunnelEstimatedPosition = estimated;
    if (firstEstimate) {
      
    }
    _updateNavigationProgress(estimated, nav, estimated: true);
    setState(() {});
  }

  void _clearLongTunnelEstimate({bool notify = false}) {
    final hadEstimate = _tunnelEstimatedPosition != null;
    _tunnelEstimatedPosition = null;
    _tunnelEstimateStartedAt = null;
    _lastTunnelEstimateAt = null;
    _longTunnelEstimateExhausted = false;
    if (notify && hadEstimate && mounted) setState(() {});
  }

  double _projectRouteProgressMeters(
    VehiclePosition position,
    List<LatLng> geometry,
  ) {
    if (geometry.length < 2) return 0;
    var bestDistance = double.infinity;
    var bestProgress = 0.0;
    var prefix = 0.0;
    for (var i = 0; i < geometry.length - 1; i++) {
      final a = geometry[i];
      final b = geometry[i + 1];
      final projected = _projectOnSegment(position.lat, position.lng, a, b);
      if (projected.distanceMeters < bestDistance) {
        bestDistance = projected.distanceMeters;
        bestProgress = prefix + projected.segmentMeters * projected.t;
      }
      prefix += projected.segmentMeters;
    }
    return bestProgress;
  }

  /// همان منطقِ [_projectRouteProgressMeters] اما برای یک نقطه‌ی دلخواه
  /// (نه لزوماً موقعیت خودرو) — برای فرافکنیِ محلِ هشدارهای جاده روی خطِ
  /// مسیر استفاده می‌شود.
  double _projectLatLngProgressMeters(LatLng point, List<LatLng> geometry) {
    if (geometry.length < 2) return 0;
    var bestDistance = double.infinity;
    var bestProgress = 0.0;
    var prefix = 0.0;
    for (var i = 0; i < geometry.length - 1; i++) {
      final a = geometry[i];
      final b = geometry[i + 1];
      final projected = _projectOnSegment(
        point.latitude,
        point.longitude,
        a,
        b,
      );
      if (projected.distanceMeters < bestDistance) {
        bestDistance = projected.distanceMeters;
        bestProgress = prefix + projected.segmentMeters * projected.t;
      }
      prefix += projected.segmentMeters;
    }
    return bestProgress;
  }

  Future<void> _refreshNormalRoadSnap(VehiclePosition position) async {
    if (ref.read(activeNavigationProvider) != null) return;
    final requestId = ++_normalSnapRequest;
    final engine = ref.read(routingEngineProvider);
    VehiclePosition? snapped;

    if (engine == RoutingEngine.online) {
      // RoadSafetyService already reads nearby OSM road geometry. Reuse its
      // matched point once the asynchronous refresh completes.
      final matched = _roadSafety.roadMatchedPosition;
      if (matched != null && _distanceBetween(
            LatLng(position.lat, position.lng),
            matched,
          ) <= (position.isEstimated ? 45.0 : 35.0)) {
        snapped = VehiclePosition(
          lat: matched.latitude,
          lng: matched.longitude,
          headingDeg: _roadSafety.roadHeadingDeg ?? position.headingDeg,
          speedKmh: position.speedKmh,
          accuracyM: math.max(position.accuracyM,
              _distanceBetween(LatLng(position.lat, position.lng), matched)),
          isEstimated: position.isEstimated,
        );
      }
    } else {
      final file = ref.read(activeOfflineMapFileProvider).valueOrNull;
      snapped = await _offlineRoadSnapService.snap(position, file);
    }

    if (!mounted || requestId != _normalSnapRequest ||
        ref.read(activeNavigationProvider) != null) return;
    final current = ref.read(vehiclePositionProvider).valueOrNull;
    if (current != null && snapped != null) {
      final drift = _distanceBetween(
        LatLng(current.lat, current.lng),
        LatLng(snapped.lat, snapped.lng),
      );
      if (drift > (current.isEstimated ? 60.0 : 45.0)) return;
    }
    setState(() {
      _normalSnappedVehiclePosition = snapped;
      _normalSnapSourceAt = DateTime.now();
    });
  }

  Future<void> _refreshRoadSafety(VehiclePosition position) async {
    if (_roadSafetyRequestInFlight) return;
    final center = LatLng(position.lat, position.lng);
    final now = DateTime.now();
    final lastCenter = _lastRoadSafetyCenter;
    if (_lastRoadSafetyUpdate != null &&
        now.difference(_lastRoadSafetyUpdate!) < const Duration(seconds: 8) &&
        lastCenter != null &&
        _distanceBetween(center, lastCenter) < 70) {
      return;
    }
    _roadSafetyRequestInFlight = true;
    try {
      final engine = ref.read(routingEngineProvider);
      RoadSafetySnapshot snapshot;
      if (engine == RoutingEngine.online) {
        snapshot = await _roadSafetyService.online(
          center,
          preferredHeadingDeg: position.headingDeg,
        );
      } else {
        final file = ref.read(activeOfflineMapFileProvider).valueOrNull;
        if (file != null) {
          snapshot = await _roadSafetyService.offline(
            file,
            center,
            preferredHeadingDeg: position.headingDeg,
          );
        } else {
          snapshot = const RoadSafetySnapshot();
        }
      }
      if (!mounted) return;
      setState(() {
        _roadSafety = snapshot;
        _lastRoadSafetyCenter = center;
        _lastRoadSafetyUpdate = DateTime.now();
      });
      if (engine == RoutingEngine.online) {
        unawaited(_refreshNormalRoadSnap(position));
      }
      _maybeShowMovingRoadAlert(position, snapshot.alerts);
    } finally {
      _roadSafetyRequestInFlight = false;
    }
  }

  void _maybeShowMovingRoadAlert(
    VehiclePosition position,
    List<RouteAlert> alerts,
  ) {
    // During navigation the single route-based alert overlay is authoritative.
    // Do not create a second transient card from the safety layer.
    if (ref.read(activeNavigationProvider) != null) return;
    if (!mounted ||
        position.speedKmh < _movingAlertMinSpeedKmh ||
        alerts.isEmpty) {
      return;
    }

    final current = LatLng(position.lat, position.lng);
    ({RouteAlert alert, double distanceM})? best;
    var bestDistance = double.infinity;
    for (final alert in alerts) {
      final distance = _distanceBetween(current, alert.location);
      if (distance > _movingAlertDistanceM || distance >= bestDistance)
        continue;

      // فقط هشدارهای جلوی خودرو. اگر heading معتبر نباشد، فاصله به‌تنهایی
      // ملاک می‌شود تا GPSهای کم‌کیفیت باعث حذف هشدار واقعی نشوند.
      final bearing = _bearingBetween(current, alert.location);
      final delta = ((bearing - position.headingDeg + 540) % 360) - 180;
      final headingValid = position.headingDeg.isFinite;
      if (headingValid && delta.abs() > 75) continue;

      final key =
          '${alert.type.name}:${alert.location.latitude.toStringAsFixed(5)}:${alert.location.longitude.toStringAsFixed(5)}';
      final lastShown = _shownRoadAlertKeys[key];
      if (lastShown != null &&
          DateTime.now().difference(lastShown) < const Duration(seconds: 35)) {
        continue;
      }
      best = (alert: alert, distanceM: distance);
      bestDistance = distance;
    }

    if (best == null) return;
    final key =
        '${best!.alert.type.name}:${best!.alert.location.latitude.toStringAsFixed(5)}:${best!.alert.location.longitude.toStringAsFixed(5)}';
    _shownRoadAlertKeys[key] = DateTime.now();
    _transientRoadAlertTimer?.cancel();
    setState(() => _transientRoadAlert = best);
    _transientRoadAlertTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _transientRoadAlert = null);
    });

    // کش قدیمی را مرتب نگه می‌داریم.
    final cutoff = DateTime.now().subtract(const Duration(minutes: 3));
    _shownRoadAlertKeys.removeWhere((_, time) => time.isBefore(cutoff));
  }

  double _distanceBetween(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180.0;
    final dLng = (b.longitude - a.longitude) * math.pi / 180.0;
    final aa =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(a.latitude * math.pi / 180.0) *
            math.cos(b.latitude * math.pi / 180.0) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(aa), math.sqrt(1 - aa));
  }

  List<({RouteAlert alert, double distanceM})> _displayRoadAlerts(
    ActiveNavigation? navigation,
  ) {
    // در حالت مسیریابی فقط هشدارِ بعدیِ روی خودِ مسیر نمایش داده می‌شود.
    // این باعث می‌شود دو کارت زیر هم، یا هشدار مربوط به خیابان موازی، ظاهر نشود.
    if (navigation == null) return const [];

    final upcoming = _upcomingAlerts(navigation);
    if (upcoming.isNotEmpty) return upcoming;

    // برای موتور آنلاین ممکن است route.alerts خالی باشد؛ در این حالت فقط
    // نزدیک‌ترین هشدارِ لایه‌ی ایمنی را تا 100 متر قبول می‌کنیم.
    final position =
        _tunnelEstimatedPosition ??
        ref.read(navigationPositionProvider).valueOrNull;
    if (position == null) return const [];

    final current = LatLng(position.lat, position.lng);
    ({RouteAlert alert, double distanceM})? best;
    for (final alert in _roadSafety.alerts) {
      final distance = _distanceBetween(current, alert.location);
      if (distance > _alertDisplayRangeM) continue;
      if (position.headingDeg.isFinite) {
        final bearing = _bearingBetween(current, alert.location);
        final delta = ((bearing - position.headingDeg + 540) % 360) - 180;
        if (delta.abs() > 75) continue;
      }
      if (best == null || distance < best!.distanceM) {
        best = (alert: alert, distanceM: distance);
      }
    }
    return best == null ? const [] : [best!];
  }

  /// فاصله‌ی (بر حسب متر از ابتدای مسیر) هر هشدارِ [RouteAlert] را یک‌بار
  /// در ازای هر مسیر محاسبه و کش می‌کند — این تصویر روی خطِ مسیر تغییر
  /// نمی‌کند، پس نیازی به محاسبه‌ی دوباره در هر فریم نیست.
  List<double> _ensureRouteAlertProgress(RouteInfo route) {
    if (identical(_routeAlertsSource, route.alerts) &&
        _routeAlertsProgressM != null) {
      return _routeAlertsProgressM!;
    }
    _routeAlertsSource = route.alerts;
    _routeAlertsProgressM = route.alerts
        .map(
          (alert) =>
              _projectLatLngProgressMeters(alert.location, route.geometry),
        )
        .toList(growable: false);
    return _routeAlertsProgressM!;
  }

  /// پیشرفتِ (متر از ابتدای مسیر) هر مانورِ مسیریابی، کش‌شده به‌ازای هر
  /// مسیر. نگاه کنید به کامنتِ بالای [_routeInstructionsProgressM].
  List<double> _ensureRouteInstructionProgress(RouteInfo route) {
    if (identical(_routeInstructionsSource, route.instructions) &&
        _routeInstructionsProgressM != null) {
      return _routeInstructionsProgressM!;
    }
    _routeInstructionsSource = route.instructions;
    _routeInstructionsProgressM = route.instructions
        .map(
          (instr) =>
              _projectLatLngProgressMeters(instr.location, route.geometry),
        )
        .toList(growable: false);
    return _routeInstructionsProgressM!;
  }

  /// حداکثر تعداد هشدارهایی که هم‌زمان زیر هم نمایش داده می‌شوند (مثلاً
  /// چراغ راهنمایی + دوربین سرِ یک تقاطع).
  static const int _maxStackedAlerts = 3;

  /// همه‌ی هشدارهای جلوی خودرو (دوربین/سرعت‌گیر/پلیس/چراغ راهنمایی) در
  /// محدوده‌ی [_alertDisplayRangeM]، مرتب‌شده از نزدیک به دور. اگر بیش از
  /// [_maxStackedAlerts] مورد هم‌زمان در محدوده باشند، فقط نزدیک‌ترین‌ها
  /// نگه داشته می‌شوند تا صفحه شلوغ نشود. تُلرانسِ کوچکِ عقب (۲۵ متر)
  /// اجازه می‌دهد هشدار درست لحظه‌ی عبور از کنارش هنوز محو نشود.
  List<({RouteAlert alert, double distanceM})> _upcomingAlerts(
    ActiveNavigation navigation,
  ) {
    final alerts = navigation.route.alerts;
    if (alerts.isEmpty) return const [];
    final currentProgressM = _routeMatchLastProgressM;
    if (currentProgressM == null) return const [];
    final progressList = _ensureRouteAlertProgress(navigation.route);

    final matches = <({RouteAlert alert, double distanceM})>[];
    for (var i = 0; i < alerts.length; i++) {
      final remaining = progressList[i] - currentProgressM;
      if (remaining < 0 || remaining > _alertDisplayRangeM) continue;
      matches.add((
        alert: alerts[i],
        distanceM: remaining.clamp(0.0, double.infinity),
      ));
    }
    matches.sort((a, b) => a.distanceM.compareTo(b.distanceM));
    if (matches.length > _maxStackedAlerts) {
      matches.removeRange(_maxStackedAlerts, matches.length);
    }
    return matches;
  }

  /// Snap دائمی خودرو به نزدیک‌ترین قطعهٔ خیابان مسیر. زاویه از خودِ قطعه
  /// استخراج می‌شود تا تکان قطب‌نما یا heading خام GPS نتواند خودرو را به
  /// پهلو بچرخاند. بیرون از حریم 45 متری مسیر، دادهٔ خام حفظ می‌شود تا
  /// تشخیص خروج از مسیر همچنان ممکن باشد.
  ///
  /// باگِ قبلی («خودرو هنگام مسیریابی می‌پرد»): این تابع هر بار (تا با نرخ
  /// ۶۰fps از navigationPositionProvider) نزدیک‌ترین نقطه را با یک
  /// جست‌وجوی *سراسری* روی کل segmentهای مسیر پیدا می‌کرد — بدون هیچ
  /// حافظه‌ای از پیشرفتِ قبلی. در هر مسیری که از نزدیکیِ خودش دوباره رد
  /// می‌شود (لِینِ برگشت، دوربرگردان، رمپِ بزرگراه، دو خیابانِ موازیِ
  /// نزدیک به هم)، یک فیکسِ GPS با چند متر خطا کافی بود که نزدیک‌ترین‌نقطه
  /// یک‌دفعه از segmentِ درستِ جلوی خودرو به segmentِ دیگری (جلوتر یا حتی
  /// عقب‌تر روی مسیر) عوض شود — یعنی همان پرشِ گزارش‌شده، چون هم مارکر و
  /// هم دوربینِ دنبال‌کننده مستقیماً از خروجیِ همین تابع تغذیه می‌کنند.
  ///
  /// راه‌حل: بعد از اولین تطبیق، فقط در یک پنجره‌ی محدود (بر حسب متر، نه
  /// ایندکس) حولِ آخرین پیشرفتِ شناخته‌شده جست‌وجو می‌کنیم — پیشرفتِ مسیر
  /// نمی‌تواند در یک تیک به بخشِ کاملاً دیگری از مسیر بپرد. فقط اگر داخلِ
  /// همان پنجره چیزِ نزدیکی (کمتر از ۴۵ متر) پیدا نشد (فیکس گم شده،
  /// دوباره‌مسیریابی، شروعِ ناوبری) به جست‌وجوی کاملِ مسیر برمی‌گردیم.
  VehiclePosition? _matchPositionToRoute(
    VehiclePosition position,
    List<LatLng> geometry,
  ) {
    if (geometry.length < 2) return null;
    // موقعیت شبکه‌ای/فیکس کم‌دقت را به‌زور به مسیر نمی‌چسبانیم؛ این کار به‌ویژه
    // پس از بازگشت از تونل باعث انتخاب شاخهٔ موازی و پرش بزرگ خودرو می‌شد.
    final maxAccuracyM = position.isEstimated ? 120.0 : 30.0;
    if (!position.accuracyM.isFinite || position.accuracyM > maxAccuracyM) {
      return null;
    }

    if (!identical(_routeMatchGeometry, geometry)) {
      _routeMatchGeometry = geometry;
      _routeMatchCumulativeM = _buildCumulativeDistances(geometry);
      _routeMatchLastSegment = null;
      _routeMatchLastProgressM = null;
    }
    final cumulative = _routeMatchCumulativeM!;
    final lastSegmentCount = geometry.length - 2;

    const backWindowM = 80.0;
    const aheadWindowM = 500.0;
    var startIdx = 0;
    var endIdx = lastSegmentCount;
    final lastIdx = _routeMatchLastSegment;
    if (lastIdx != null && lastIdx >= 0 && lastIdx <= lastSegmentCount) {
      final lastProgress = cumulative[lastIdx];
      final lo = lastProgress - backWindowM;
      final hi = lastProgress + aheadWindowM;
      var s = lastIdx;
      while (s > 0 && cumulative[s] > lo) s--;
      var e = lastIdx;
      while (e < lastSegmentCount && cumulative[e] < hi) e++;
      startIdx = s;
      endIdx = e;
    }

    var best = _bestSegmentMatch(position, geometry, startIdx, endIdx);
    if (best == null || best.distanceMeters > 45) {
      // پنجره چیزِ نزدیکی نداشت — بازگشت به جست‌وجوی کاملِ مسیر.
      best = _bestSegmentMatch(position, geometry, 0, lastSegmentCount);
    }
    if (best == null || best.distanceMeters > 45) {
      return null;
    }

    final progressM =
        cumulative[best.segmentIndex] +
        best.projection.segmentMeters * best.projection.t;
    final lastProgressM = _routeMatchLastProgressM;
    // وقتی مسیر از نزدیک خودش عبور می‌کند یا GPS یک فیکس عقب می‌فرستد، نزدیک‌ترین
    // قطعه می‌تواند ده‌ها متر پشت خودرو باشد. این مقدار نباید مستقیم به marker
    // برگردد، زیرا animation این مرحله را پشت سر گذاشته است. پس فقط نوسان کوچک
    // ۱۵ متری مجاز است؛ برگشت بزرگ تا فیکس/مسیر معتبر بعدی نگه داشته می‌شود.
    if (lastProgressM != null && progressM < lastProgressM - 15.0) {
      final held = _routeSampleAtMeters(geometry, lastProgressM);
      if (held != null) {
        return VehiclePosition(
          lat: held.point.latitude,
          lng: held.point.longitude,
          headingDeg: held.headingDeg,
          speedKmh: position.speedKmh,
          accuracyM: position.accuracyM,
          isEstimated: position.isEstimated,
        );
      }
      return null;
    }

    _routeMatchLastSegment = best.segmentIndex;
    _routeMatchLastProgressM = progressM;
    final a = geometry[best.segmentIndex];
    final b = geometry[best.segmentIndex + 1];
    final t = best.projection.t;
    return VehiclePosition(
      lat: a.latitude + (b.latitude - a.latitude) * t,
      lng: a.longitude + (b.longitude - a.longitude) * t,
      headingDeg: _bearingBetween(a, b),
      speedKmh: position.speedKmh,
      accuracyM: position.accuracyM,
      isEstimated: position.isEstimated,
    );
  }

  _RouteMatch? _bestRouteMatchNearProgress(
    VehiclePosition position,
    List<LatLng> geometry,
    double progressM,
  ) {
    if (geometry.length < 2) return null;
    final cumulative =
        _routeMatchCumulativeM ?? _buildCumulativeDistances(geometry);
    const backWindowM = 35.0;
    const aheadWindowM = 180.0;
    final lo = math.max(0.0, progressM - backWindowM);
    final hi = math.min(cumulative.last, progressM + aheadWindowM);
    var startIdx = 0;
    while (startIdx < geometry.length - 2 && cumulative[startIdx + 1] < lo) {
      startIdx++;
    }
    var endIdx = startIdx;
    while (endIdx < geometry.length - 2 && cumulative[endIdx] < hi) {
      endIdx++;
    }
    final match = _bestSegmentMatch(position, geometry, startIdx, endIdx);
    if (match == null || match.distanceMeters > 65.0) return null;
    return match;
  }

  _RouteMatch? _bestSegmentMatch(
    VehiclePosition position,
    List<LatLng> geometry,
    int startIdx,
    int endIdx,
  ) {
    var bestDistance = double.infinity;
    _RouteMatch? best;
    for (var i = startIdx; i <= endIdx; i++) {
      final a = geometry[i];
      final b = geometry[i + 1];
      final projection = _projectOnSegment(position.lat, position.lng, a, b);
      if (projection.distanceMeters < bestDistance) {
        bestDistance = projection.distanceMeters;
        best = _RouteMatch(segmentIndex: i, projection: projection);
      }
    }
    return best;
  }

  List<double> _buildCumulativeDistances(List<LatLng> geometry) {
    final cumulative = List<double>.filled(geometry.length, 0);
    for (var i = 1; i < geometry.length; i++) {
      cumulative[i] =
          cumulative[i - 1] + _calculateDistance(geometry[i - 1], geometry[i]);
    }
    return cumulative;
  }

  _RouteSample? _routeSampleAtMeters(List<LatLng> geometry, double meters) {
    if (geometry.length < 2) return null;
    var remaining = meters.clamp(0.0, double.infinity).toDouble();
    var prefix = 0.0;
    for (var i = 0; i < geometry.length - 1; i++) {
      final a = geometry[i];
      final b = geometry[i + 1];
      final segment = _calculateDistance(a, b);
      if (segment <= 0.01) continue;
      if (remaining <= segment || i == geometry.length - 2) {
        final t = (remaining / segment).clamp(0.0, 1.0).toDouble();
        return _RouteSample(
          LatLng(
            a.latitude + (b.latitude - a.latitude) * t,
            a.longitude + (b.longitude - a.longitude) * t,
          ),
          _bearingBetween(a, b),
          prefix + segment * t,
        );
      }
      remaining -= segment;
      prefix += segment;
    }
    final last = geometry.last;
    return _RouteSample(last, 0.0, prefix);
  }

  _SegmentProjection _projectOnSegment(
    double lat,
    double lng,
    LatLng a,
    LatLng b,
  ) {
    const metersPerDegree = 111320.0;
    final cosLat = math.cos(((a.latitude + b.latitude) / 2) * math.pi / 180);
    final bx = (b.longitude - a.longitude) * metersPerDegree * cosLat;
    final by = (b.latitude - a.latitude) * metersPerDegree;
    final px = (lng - a.longitude) * metersPerDegree * cosLat;
    final py = (lat - a.latitude) * metersPerDegree;
    final segmentSquared = bx * bx + by * by;
    final t =
        (segmentSquared <= 0
                ? 0.0
                : ((px * bx + py * by) / segmentSquared).clamp(0.0, 1.0))
            .toDouble();
    final dx = px - bx * t;
    final dy = py - by * t;
    return _SegmentProjection(
      t: t,
      segmentMeters: math.sqrt(segmentSquared),
      distanceMeters: math.sqrt(dx * dx + dy * dy),
    );
  }

  double _bearingBetween(LatLng a, LatLng b) {
    final y =
        (b.longitude - a.longitude) *
        math.cos((a.latitude + b.latitude) * math.pi / 360);
    final x = b.latitude - a.latitude;
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  Future<void> _stopNavigation() async {
    // نخست source نیتیو را خالی می‌کنیم؛ حذف state نباید باعث باقی‌ماندن
    // خط مسیر روی MapLibre شود.
    await _clearRoute();
    ref.read(navigationPositionControllerProvider).clearActiveRoute();
    ref.read(activeNavigationProvider.notifier).clear();
    ref.read(selectedDestinationProvider.notifier).state = null;
    await ref.read(ttsServiceProvider).stop();
    _offRouteStrikeCount = 0;
    _offRouteSince = null;
    _previousValidationPosition = null;
    _previousValidationAt = null;
    _recentMovementBearingDeg = null;
    _isRerouting = false;
    _lastRerouteAt = null;
    _clearLongTunnelEstimate();
    _routeMatchGeometry = null;
    _routeMatchCumulativeM = null;
    _routeMatchLastSegment = null;
    _routeMatchLastProgressM = null;
    _routeAlertsSource = null;
    _routeAlertsProgressM = null;
    _routeInstructionsSource = null;
    _routeInstructionsProgressM = null;

    // غیرفعال کردن حالت رانندگی
    ref.read(drivingModeProvider.notifier).state = false;

    // Returning from navigation must restore the normal driving-follow mode;
    // the map should keep tracking the road direction even with no route.
    _cameraFollowsVehicle = true;
    setState(() {});
  }

  double? _routeHeadingNearPosition(LatLng point, List<LatLng> geometry) {
    if (geometry.length < 2) return null;
    var best = double.infinity;
    double? heading;
    for (var i = 0; i < geometry.length - 1; i++) {
      final d = _distanceToSegmentMeters(point, geometry[i], geometry[i + 1]);
      if (d < best) {
        best = d;
        heading = _bearingBetween(geometry[i], geometry[i + 1]);
      }
    }
    return heading;
  }

  double _angleDifference(double a, double b) =>
      ((a - b + 540.0) % 360.0) - 180.0;

  void _updateNavigationProgress(
    VehiclePosition pos,
    ActiveNavigation nav, {
    bool estimated = false,
    VehiclePosition? gpsValidationPosition,
  }) {
    final currentLoc = LatLng(pos.lat, pos.lng);
    final validation = gpsValidationPosition ?? pos;
    final validationLoc = LatLng(validation.lat, validation.lng);

    // Update real movement bearing BEFORE route validation. A previous version
    // performed this calculation after the off-route check, so the validator
    // used a stale heading exactly during the first sample after a missed turn.
    final previousAt = _previousValidationAt;
    final previous = _previousValidationPosition;
    if (previous != null && previousAt != null && !validation.isEstimated) {
      final now = DateTime.now();
      final dt = now.difference(previousAt).inMilliseconds / 1000.0;
      final moved = _distanceBetween(
        LatLng(previous.lat, previous.lng),
        validationLoc,
      );
      if (dt > 0.12 && dt < 3.0 && moved >= 2.0) {
        _recentMovementBearingDeg = _bearingBetween(
          LatLng(previous.lat, previous.lng),
          validationLoc,
        );
      }
    }
    _previousValidationPosition = validation;
    _previousValidationAt = DateTime.now();

    // Only the animated position owns visual route progress. This keeps the
    // maneuver distance and the 100m warning threshold moving continuously.
    if (!estimated) {
      _matchPositionToRoute(pos, nav.route.geometry);
    }

    if (!estimated &&
        nav.state == NavigationState.navigating &&
        !_isRerouting) {
      final routeMatch = _bestRouteMatchNearProgress(
        validation,
        nav.route.geometry,
        _routeMatchLastProgressM ??
            _projectRouteProgressMeters(validation, nav.route.geometry),
      );
      final distFromRoute = routeMatch?.distanceMeters ?? double.infinity;
      final routeHeading = routeMatch == null
          ? null
          : _bearingBetween(
              nav.route.geometry[routeMatch.segmentIndex],
              nav.route.geometry[routeMatch.segmentIndex + 1],
            );

      // GPS heading can lag during a turn. Prefer the bearing of the actual
      // movement between consecutive fixes whenever enough displacement is
      // available; fall back to the provider heading otherwise.
      final movementHeading = _recentMovementBearingDeg;
      final headingForValidation = movementHeading ?? validation.headingDeg;
      final headingMismatch =
          validation.speedKmh >= 10 &&
          routeHeading != null &&
          headingForValidation.isFinite &&
          _angleDifference(headingForValidation, routeHeading).abs() > 50.0;

      // A 45m corridor + three 1Hz strikes was too slow for a missed turn.
      // A clean GPS fix on another road is enough immediately; noisier fixes
      // get one confirmation sample. The route comparison is constrained to
      // the current progress window, so a nearby parallel/future road cannot
      // falsely validate the driver's position.
      const offRouteThresholdM = 18.0;
      final highConfidenceDeviation =
          validation.accuracyM <= 12.0 &&
          validation.speedKmh >= 8.0 &&
          (distFromRoute > offRouteThresholdM || headingMismatch);
      final wrongStreetOrDirection =
          distFromRoute > offRouteThresholdM ||
          (headingMismatch && distFromRoute >= 8.0 && distFromRoute <= 90.0);

      final now = DateTime.now();
      if (wrongStreetOrDirection) {
        _offRouteSince ??= now;
        _offRouteStrikeCount++;
      } else {
        _offRouteStrikeCount = 0;
        _offRouteSince = null;
      }

      // A single bad GNSS sample must never trigger a reroute. Require a
      // continuous off-route interval; high-confidence deviations may be
      // confirmed sooner, while ordinary/noisy fixes get a longer hysteresis.
      final outsideFor = _offRouteSince == null
          ? Duration.zero
          : now.difference(_offRouteSince!);
      final requiredOutside = highConfidenceDeviation && distFromRoute >= 30.0
          ? const Duration(seconds: 1, milliseconds: 200)
          : const Duration(seconds: 2, milliseconds: 500);
      final cooldownOk =
          _lastRerouteAt == null ||
          now.difference(_lastRerouteAt!) > const Duration(seconds: 8);

      if (_offRouteStrikeCount >= 2 &&
          outsideFor >= requiredOutside &&
          cooldownOk) {
        _offRouteStrikeCount = 0;
        _offRouteSince = null;
        _rerouteOffPath(distFromRoute, gpsPosition: validation);
        return;
      }
    }

    final lastIndex = nav.route.instructions.length - 1;
    final instructionProgressM = _ensureRouteInstructionProgress(nav.route);

    // پیشرفتِ خودرو روی خودِ پلی‌لاینِ مسیر (نه خطِ‌مستقیم). اگر هنوز
    // snap موفق نشده (مثلاً همین لحظه‌ی شروعِ ناوبری)، به‌جایش پیشرفتِ
    // نزدیک‌ترین نقطه‌ی مسیر به موقعیتِ خام محاسبه می‌شود.
    final vehicleProgressM =
        _routeMatchLastProgressM ??
        _projectLatLngProgressMeters(currentLoc, nav.route.geometry);

    // مانورِ شماره‌ی صفر معمولاً همان نقطه‌ی مبدأ («حرکت را آغاز کنید»)
    // است؛ به‌محضِ آنکه خودرو از آن دور شد باید به مانورِ بعدی سوییچ کنیم.
    // برخلافِ قبل که این کار با فاصله‌ی مستقیم (که در پیچ‌ها/مسیرهای غیرِ
    // مستقیم گمراه‌کننده بود) انجام می‌شد، حالا صرفاً از پیشرفتِ روی مسیر
    // استفاده می‌شود: تا وقتی پیشرفتِ خودرو از پیشرفتِ مانورِ فعلی گذشته،
    // برو به مانورِ بعدی.
    int nearestInstructionIndex = nav.currentInstructionIndex;
    // Keep a roundabout instruction active until the vehicle has actually
    // left the circle. The next turn must not replace the selected-exit
    // guidance while the driver is still entering or circulating.
    while (nearestInstructionIndex < lastIndex) {
      final instruction = nav.route.instructions[nearestInstructionIndex];
      var completionProgress =
          instructionProgressM[nearestInstructionIndex] + 5.0;
      final endLocation = instruction.maneuverEndLocation;
      if (endLocation != null &&
          (instruction.type == 'roundabout' ||
              instruction.type == 'rotary')) {
        completionProgress = math.max(
          completionProgress,
          _projectLatLngProgressMeters(endLocation, nav.route.geometry) + 12.0,
        );
      }
      if (vehicleProgressM <= completionProgress) break;
      nearestInstructionIndex++;
    }

    final currentInstruction =
        nav.route.instructions[nearestInstructionIndex];
    var nextTargetProgress = instructionProgressM[nearestInstructionIndex];
    if ((currentInstruction.type == 'roundabout' ||
            currentInstruction.type == 'rotary') &&
        currentInstruction.maneuverEndLocation != null &&
        vehicleProgressM >= nextTargetProgress) {
      nextTargetProgress = _projectLatLngProgressMeters(
        currentInstruction.maneuverEndLocation!, nav.route.geometry,
      );
    }
    final distToNext = math.max(
      0.0,
      nextTargetProgress - vehicleProgressM,
    );
    // فاصله‌ی باقی‌مانده تا مقصد باید از موقعیتِ واقعیِ خودرو روی مسیر
    // محاسبه شود، نه با جمعِ طولِ کاملِ هر مانورِ باقی‌مانده — جمعِ
    // distanceMeters هر مانور، طولِ کاملِ آن قطعه را حساب می‌کند و بخشِ
    // طی‌شده از مانورِ فعلی را هم اشتباهاً به باقی‌مانده اضافه می‌کند.
    final distToDestination = math.max(
      0.0,
      instructionProgressM[lastIndex] - vehicleProgressM,
    );

    ref
        .read(activeNavigationProvider.notifier)
        .updateProgress(
          nearestInstructionIndex,
          distToDestination / 1000,
          distanceToNextManeuverM: distToNext,
        );

    // ---- زمان‌بندی اعلام‌های صوتی ----
    // پیش‌تر فقط با «عوض‌شدن ایندکس مانور» یک‌بار حرف زده می‌شد؛ برای همین
    // پیام‌ها گاهی خیلی زود (وقتی هنوز صدها متر مانده) یا خیلی دیر (وقتی از
    // پیچ رد شده بودی) پخش می‌شدند. حالا اعلام‌ها بر اساس فاصلهٔ واقعی تا
    // مانور و سرعت خودرو در مرحله‌های استاندارد پخش می‌شوند.
    if (nearestInstructionIndex != _lastSpokenInstructionIndex) {
      _lastSpokenInstructionIndex = nearestInstructionIndex;
      // مرحله‌های مانورهای گذشته دیگر لازم نیستند.
      _spokenStages.removeWhere((key) => key ~/ 10 < nearestInstructionIndex);
    }

    if (ref.read(ttEnabledProvider)) {
      final instr = nav.route.instructions[nearestInstructionIndex];
      final speedKmh =
          ref.read(navigationPositionProvider).value?.speedKmh ?? 0;
      final speedMs = (speedKmh / 3.6).clamp(0.0, 60.0);

      // فاصلهٔ «اعلام فوری» با سرعت بالا می‌رود تا صدا دقیقاً قبل از پیچ
      // تمام شود (تقریباً ۶ ثانیه جلوتر، حداقل ۴۰ و حداکثر ۱۵۰ متر).
      final imminentAt = (speedMs * 6).clamp(40.0, 150.0);
      final firstAlert = ref
          .read(voiceFirstAlertDistanceProvider)
          .clamp(50.0, 1000.0);
      final stages = <int, double>{
        0: firstAlert,
        1: (firstAlert * 0.5).clamp(50.0, firstAlert),
        2: (firstAlert * 0.2).clamp(40.0, firstAlert),
        3: imminentAt.clamp(40.0, firstAlert),
      };

      int? stageToSpeak;
      for (final entry in stages.entries) {
        final key = nearestInstructionIndex * 10 + entry.key;
        if (_spokenStages.contains(key)) continue;
        if (distToNext <= entry.value) {
          // مرحله‌های دورتری که رد شده‌ایم را بدون حرف‌زدن مصرف‌شده می‌کنیم.
          _spokenStages.add(key);
          stageToSpeak = entry.key;
        }
      }

      // فقط نزدیک‌ترین مرحلهٔ فعال گفته می‌شود (نه چند پیام پشت‌سرهم).
      if (stageToSpeak != null) {
        final voice = ref.read(ttsServiceProvider)
          ..setVolume(ref.read(ttsVolumeProvider))
          ..setPlaybackRate(ref.read(ttsRateProvider));

        voice.playCue(
          VoicePackFa.cueForManeuver(
            type: instr.type,
            modifier: instr.modifier,
            exit: instr.exit,
          ),
        );
      }
    }

    if (!_arrivalHandled &&
        distToDestination < 20 &&
        nearestInstructionIndex >= lastIndex) {
      _arrivalHandled = true;
      _onArrived();
    }
  }

  double _distanceToRouteMeters(LatLng p, List<LatLng> geometry) {
    if (geometry.isEmpty) return double.infinity;
    if (geometry.length == 1) return _calculateDistance(p, geometry.first);

    double minDist = double.infinity;
    for (var i = 0; i < geometry.length - 1; i++) {
      final d = _distanceToSegmentMeters(p, geometry[i], geometry[i + 1]);
      if (d < minDist) minDist = d;
    }
    return minDist;
  }

  double _distanceToSegmentMeters(LatLng p, LatLng a, LatLng b) {
    const metersPerDegLat = 111320.0;
    final metersPerDegLng = 111320.0 * math.cos(degToRad(p.latitude));

    double toX(LatLng q) => (q.longitude - a.longitude) * metersPerDegLng;
    double toY(LatLng q) => (q.latitude - a.latitude) * metersPerDegLat;

    const ax = 0.0, ay = 0.0;
    final bx = toX(b), by = toY(b);
    final px = toX(p), py = toY(p);

    final dx = bx - ax, dy = by - ay;
    final lenSq = dx * dx + dy * dy;
    var t = lenSq == 0 ? 0.0 : ((px - ax) * dx + (py - ay) * dy) / lenSq;
    t = t.clamp(0.0, 1.0);
    final projX = ax + t * dx, projY = ay + t * dy;
    final ddx = px - projX, ddy = py - projY;
    return math.sqrt(ddx * ddx + ddy * ddy);
  }

  double _calculateDistance(LatLng point1, LatLng point2) {
    const earthRadius = 6371000.0;

    final lat1 = degToRad(point1.latitude);
    final lat2 = degToRad(point2.latitude);
    final dLat = degToRad(point2.latitude - point1.latitude);
    final dLng = degToRad(point2.longitude - point1.longitude);

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  void _onArrived() {
    _showGlassNotice(
      AppStrings.literal('به مقصد رسیدید!'),
      icon: Icons.flag_rounded,
      colors: const [AppColors.speedLow, Color(0xFF10D15C)],
    );
    if (ref.read(ttEnabledProvider)) {
      final voice = ref.read(ttsServiceProvider);
      voice.playCue(VoicePackFa.arrived);
    }

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _stopNavigation();
      }
    });
  }
}

class _GpsWarningBanner extends ConsumerWidget {
  final LocationReadiness state;
  const _GpsWarningBanner({super.key, required this.state});

  String get _message {
    switch (state) {
      case LocationReadiness.serviceDisabled:
        return 'GPS دستگاه خاموش است. لطفاً آن را روشن کنید.';
      case LocationReadiness.permissionDenied:
        return 'برای ناوبری به مجوز موقعیت مکانی نیاز است. (ضربه بزنید تا دوباره بپرسیم)';
      case LocationReadiness.permissionDeniedForever:
        return 'مجوز موقعیت مکانی رد شده. برای فعال‌سازی از تنظیمات، ضربه بزنید.';
      case LocationReadiness.ready:
        return '';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: state == LocationReadiness.ready
          ? null
          : () => ref.read(retryLocationPermissionProvider)(),
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
          decoration: BoxDecoration(
            color: const Color(0xFF1B1712).withOpacity(.72),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFFFB84D).withOpacity(.35)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF8A00).withOpacity(.22),
                blurRadius: 22,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFFFFB84D), Color(0xFFFF7A00)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(
                  Icons.gps_off_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  AppStrings.literal(_message),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// وقتی مجوز و سرویس مکان هر دو آماده‌اند اما بعد از مدتی معقول هنوز هیچ
/// فیکس GPS نرسیده (به‌جای سکوت کامل قبلی — نگاه کنید به
/// [_HomeScreenState._armGpsAcquireWatchdog]).
class _EstimatedLocationBanner extends StatelessWidget {
  const _EstimatedLocationBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xE6233B55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF75D6FF).withOpacity(.55)),
      ),
      child: Row(
        children: [
          Icon(Icons.network_check_rounded, color: Color(0xFF9FE7FF), size: 19),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              AppStrings.literal('موقعیت تخمینی است؛ در انتظار بازگشت GPS'),
              style: TextStyle(color: Colors.white, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _GpsStuckBanner extends StatelessWidget {
  final VoidCallback onRetry;
  const _GpsStuckBanner({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onRetry,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1B1712).withOpacity(.72),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xFFFFB84D).withOpacity(.35),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF8A00).withOpacity(.22),
                  blurRadius: 22,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFFFFB84D), Color(0xFFFF7A00)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Icon(
                    Icons.gps_not_fixed_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    AppStrings.literal(
                        'دریافت موقعیت GPS بیش از حد معمول طول کشیده. مطمئن شوید در فضای باز هستید، سپس برای تلاش دوباره ضربه بزنید.'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RouteChoiceStrip extends ConsumerWidget {
  const _RouteChoiceStrip({
    required this.routes,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<RouteInfo> routes;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = AppColors.primaryAccent(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.frameBackground(context).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          children: [
            for (var index = 0; index < routes.length; index++)
              Expanded(
                child: GestureDetector(
                  onTap: () => onSelect(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    margin: EdgeInsets.only(
                      right: index == 0 ? 4 : 0,
                      left: index == routes.length - 1 ? 4 : 0,
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 4,
                    ),
                    decoration: BoxDecoration(
                      color: index == selectedIndex
                          ? accent.withValues(alpha: 0.22)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                      border: index == selectedIndex
                          ? Border.all(color: accent, width: 1.2)
                          : null,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          index == selectedIndex
                              ? AppStrings.get(context, ref, 'route_selected')
                              : AppStrings.getWithParams(
                                  context,
                                  ref,
                                  'route_numbered',
                                  {'value': index + 1},
                                ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: index == selectedIndex
                                ? accent
                                : Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          AppStrings.getWithParams(
                            context,
                            ref,
                            'route_duration_minutes',
                            {'value': routes[index].durationMin.round()},
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          AppStrings.getWithParams(
                            context,
                            ref,
                            'route_distance_km',
                            {
                              'value': routes[index].distanceKm.toStringAsFixed(
                                1,
                              ),
                            },
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// دکمهٔ «شروع مسیریابی»: با یک تپ، به‌جای پرشِ فوری به ناوبری، رنگِ
/// دکمه طیِ ۱۰ ثانیه از حالتِ خاموش به گرادیانِ کامل پر می‌شود. اگر
/// کاربر طیِ این مدت مسیرِ دیگری را از نوارِ گزینه‌ها انتخاب نکند، همان
/// مسیرِ فعال/هایلایت‌شده در پایانِ پرشدنِ رنگ به‌طور خودکار شروع می‌شود؛
class _StartRoutingButton extends ConsumerWidget {
  const _StartRoutingButton({
    required this.enabled,
    required this.onConfirm,
  });

  final bool enabled;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: enabled ? onConfirm : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: enabled
              ? AppColors.surfaceMuted(context)
              : const Color(0xFF334155),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.navigation_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              !enabled
                  ? AppStrings.get(context, ref, 'finding_route_options')
                  : AppStrings.get(context, ref, 'start_button'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DestinationCard extends ConsumerWidget {
  final SelectedDestination destination;
  final VoidCallback onClear;
  final VoidCallback? onStartNavigation;

  const _DestinationCard({
    required this.destination,
    required this.onClear,
    required this.onStartNavigation,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.glassPanel(context),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.glassBorder(context)),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 30)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.danger.withOpacity(.15),
                      ),
                      child: const Icon(
                        Icons.location_on_rounded,
                        color: AppColors.danger,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            AppStrings.get(
                              context,
                              ref,
                              'selected_destination',
                            ),
                            style: TextStyle(
                              color: AppColors.textSecondary(context),
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            destination.label ??
                                AppStrings.get(context, ref, 'point_on_map'),
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: AppColors.textMuted(context),
                      ),
                      onPressed: onClear,
                    ),
                  ],
                ),
              ),
              Divider(
                color: AppColors.textMuted(context).withOpacity(.15),
                height: 1,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _StartRoutingButton(
                        enabled: onStartNavigation != null,
                        onConfirm: onStartNavigation,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _ActionIconButton(
                      icon: Icons.star_border_rounded,
                      onTap: () =>
                          _showSavePointDialog(context, ref, destination),
                    ),
                    const SizedBox(width: 10),
                    _ActionIconButton(
                      icon: Icons.share_rounded,
                      onTap: () {
                        final uri =
                            'https://www.google.com/maps/search/?api=1&query=${destination.point.latitude},${destination.point.longitude}';
                        ref
                            .read(shareServiceProvider)
                            .share(
                              uri,
                              subject:
                                  destination.label ??
                                  AppStrings.literal('مکان اشتراک‌گذاری شده'),
                            );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showSavePointDialog(
    BuildContext context,
    WidgetRef ref,
    SelectedDestination destination,
  ) {
    final nameController = TextEditingController(text: destination.label ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background(context),
        title: Text(
          AppStrings.get(context, ref, 'add_current_location_title'),
          style: const TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: nameController,
          autofocus: true,
          textAlign: TextAlign.right,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: AppStrings.get(context, ref, 'place_name_hint2'),
            hintStyle: TextStyle(color: AppColors.textMuted(context)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppStrings.get(context, ref, 'cancel')),
          ),
          TextButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              await ref
                  .read(savedPlacesRepositoryProvider)
                  .add(
                    name: name,
                    latitude: destination.point.latitude,
                    longitude: destination.point.longitude,
                    category: 'favorite',
                  );
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                final message = AppStrings.get(
                  context,
                  ref,
                  'point_saved_snackbar',
                );
                unawaited(
                  ref
                      .read(appNoticeProvider.notifier)
                      .show(
                        title: AppStrings.literal('آبتین مپس'),
                        message: message,
                        level: AppNoticeLevel.success,
                      ),
                );
                showGlassNotice(
                  context,
                  message,
                  icon: Icons.favorite_rounded,
                  colors: const [Color(0xFF7AD8A8), Color(0xFF3FAE73)],
                );
              }
            },
            child: Text(AppStrings.get(context, ref, 'save_label')),
          ),
        ],
      ),
    );
  }
}

class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ActionIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.glassBorder(context)),
        ),
        child: Icon(icon, color: AppColors.textSecondary(context), size: 22),
      ),
    );
  }
}

class _Compass extends StatelessWidget {
  final double mapBearingDeg;
  const _Compass({required this.mapBearingDeg});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withOpacity(.4),
        border: Border.all(color: Colors.white.withOpacity(.15)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: -mapBearingDeg * 3.1415926535 / 180,
            child: CustomPaint(
              size: const Size(56, 56),
              painter: _CompassTicksPainter(),
            ),
          ),
          // برچسبِ «N» عمداً بیرونِ Transform.rotate بالا رسم می‌شود: قبلاً
          // همراهِ کل صفحه‌ی تیک‌ها می‌چرخید، یعنی خودِ حرفِ N هم دور محورش
          // می‌چرخید و در زوایای نزدیکِ ۹۰/۲۷۰ درجه کاملاً واژگون/ناخوانا
          // (شبیهِ حرفِ Z) دیده می‌شد. اینجا فقط *موقعیتِ* برچسب دور دایره
          // با هدینگ عوض می‌شود، ولی خودِ حرف همیشه ایستاده/خوانا می‌ماند —
          // دقیقاً رفتار قطب‌نمای اپ‌های ناوبری استاندارد.
          CustomPaint(
            size: const Size(56, 56),
            painter: _CompassNorthLabelPainter(mapBearingDeg: mapBearingDeg),
          ),
          Transform.rotate(
            angle: -mapBearingDeg * 3.1415926535 / 180,
            child: CustomPaint(
              size: const Size(30, 30),
              painter: _CompassNeedlePainter(
                southColor: AppColors.textSecondary(context),
              ),
            ),
          ),
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompassNorthLabelPainter extends CustomPainter {
  final double mapBearingDeg;
  _CompassNorthLabelPainter({required this.mapBearingDeg});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    final angle = -mapBearingDeg * 3.1415926535 / 180;
    final pos = Offset(
      center.dx + radius * math.sin(angle),
      center.dy - radius * math.cos(angle),
    );
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'N',
        style: TextStyle(
          color: AppColors.danger,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(pos.dx - textPainter.width / 2, pos.dy - textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _CompassNorthLabelPainter oldDelegate) =>
      oldDelegate.mapBearingDeg != mapBearingDeg;
}

class _CompassNeedlePainter extends CustomPainter {
  final Color southColor;
  _CompassNeedlePainter({required this.southColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final tip = size.height / 2 - 2;
    final tail = size.height / 2 - 2;
    const halfWidth = 4.0;

    final northPaint = Paint()..color = AppColors.danger;
    final southPaint = Paint()..color = southColor;

    final northPath = Path()
      ..moveTo(center.dx, center.dy - tip)
      ..lineTo(center.dx - halfWidth, center.dy)
      ..lineTo(center.dx + halfWidth, center.dy)
      ..close();

    final southPath = Path()
      ..moveTo(center.dx, center.dy + tail)
      ..lineTo(center.dx - halfWidth, center.dy)
      ..lineTo(center.dx + halfWidth, center.dy)
      ..close();

    canvas.drawPath(northPath, northPaint);
    canvas.drawPath(southPath, southPaint);
  }

  @override
  bool shouldRepaint(covariant _CompassNeedlePainter oldDelegate) =>
      oldDelegate.southColor != southColor;
}

class _CompassTicksPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    final tickPaint = Paint()
      ..color = Colors.white.withOpacity(.6)
      ..strokeWidth = 1.5;

    for (var i = 0; i < 4; i++) {
      final angle = (i * 90) * 3.1415926535 / 180;
      final outer = Offset(
        center.dx + radius * math.sin(angle),
        center.dy - radius * math.cos(angle),
      );
      final inner = Offset(
        center.dx + (radius - 5) * math.sin(angle),
        center.dy - (radius - 5) * math.cos(angle),
      );
      canvas.drawLine(inner, outer, tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    this.onLongPress,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primaryAccentDark(context),
            border: Border.all(color: AppColors.glassBorder(context)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.22), blurRadius: 14),
            ],
          ),
          child: Icon(icon, color: AppColors.primaryOnAccent(context), size: 22),
        ),
      ),
    );
  }
}

class _SpeedometerDial extends StatelessWidget {
  final double value;
  const _SpeedometerDial({required this.value});

  @override
  Widget build(BuildContext context) {
    const size = 96.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withOpacity(.6),
              border: Border.all(color: Colors.white.withOpacity(.1), width: 1),
              boxShadow: const [
                BoxShadow(color: Colors.black87, blurRadius: 12),
              ],
            ),
          ),
          CustomPaint(
            size: const Size(size, size),
            painter: _GradientArcPainter(
              progress: (value / 180).clamp(0, 1),
              colors: [Colors.green, Colors.yellow, Colors.red],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value.round().toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  shadows: [
                    Shadow(
                      color: Colors.black87,
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
              Text(
                'km/h',
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 13,
                  shadows: const [
                    Shadow(
                      color: Colors.black87,
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// تابلوی محدودیت سرعت — با همان تصویرِ اسپیدومتر-مانندِ
/// `assets/images/speed-limit.webp` (صفحه‌ی مشکی/فلزی با حلقه‌ی LED قرمز).
/// قبلاً عدد با رنگ مشکی نوشته می‌شد که روی مرکز تیره‌ی این عکس دیده
/// نمی‌شد؛ رنگ عدد به سفید (هم‌رنگ با سبک اسپیدومتر) تغییر کرد.
class _SpeedLimitSign extends StatelessWidget {
  final String value;
  const _SpeedLimitSign({required this.value});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 67.0;
        final maxH = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 67.0;
        final size = math.min(maxW, maxH) > 0 ? math.min(maxW, maxH) : 67.0;
        final scale = size / 67.0;

        return Stack(
          alignment: Alignment.center,
          children: [
            Image.asset(
              'assets/images/speed-limit.webp',
              width: size,
              height: size,
              fit: BoxFit.contain,
            ),
            Text(
              value,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20 * scale,
                fontWeight: FontWeight.w900,
                shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GradientArcPainter extends CustomPainter {
  final double progress;
  final List<Color> colors;
  final double thickness;

  _GradientArcPainter({
    required this.progress,
    required this.colors,
    this.thickness = 6,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      thickness / 2,
      thickness / 2,
      size.width - thickness,
      size.height - thickness,
    );
    const startAngle = 0.75 * math.pi;
    const sweepAngle = 1.5 * math.pi;

    final backgroundPaint = Paint()
      ..color = Colors.white.withOpacity(.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, startAngle, sweepAngle, false, backgroundPaint);

    if (progress > 0) {
      final gradient = SweepGradient(
        startAngle: 0,
        endAngle: sweepAngle,
        colors: colors,
        transform: const GradientRotation(startAngle),
      );

      final paint = Paint()
        ..shader = gradient.createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(rect, startAngle, sweepAngle * progress, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GradientArcPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _ActiveNavigationCard extends ConsumerWidget {
  final ActiveNavigation navigation;
  final VoidCallback onClose;
  const _ActiveNavigationCard({
    required this.navigation,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instruction = navigation.currentInstruction;
    final remainingKm = navigation.remainingDistanceKm;
    final remainingMin = navigation.route.distanceKm > 0
        ? (navigation.route.durationMin *
                  (remainingKm / navigation.route.distanceKm))
              .round()
        : 0;
    final dNext = navigation.distanceToNextManeuverM;
    final nextText = dNext >= 1000
        ? AppStrings.getWithParams(context, ref, 'route_distance_km', {
            'value': (dNext / 1000).toStringAsFixed(1),
          })
        : AppStrings.getWithParams(context, ref, 'route_distance_m', {
            'value': dNext.round(),
          });

    final eta = DateTime.now().add(Duration(minutes: remainingMin));
    final etaText =
        '${eta.hour.toString().padLeft(2, '0')}:${eta.minute.toString().padLeft(2, '0')}';

    final appearance = ref.watch(appearanceSettingsProvider);
    final isRoundabout =
        instruction.type == 'roundabout' || instruction.type == 'rotary';

    return RouteGuidanceCard(
      settings: appearance,
      data: RouteGuidanceCardData(
        icon: _getInstructionIcon(instruction.type, instruction.modifier),
        iconWidget: isRoundabout
            ? RoundaboutManeuverIcon(
                exit: instruction.exit,
                exitCount: instruction.roundaboutExitCount,
                angleDegrees: instruction.roundaboutAngleDegrees,
                branchAngles: instruction.roundaboutBranchAngles,
                entranceAngles: instruction.roundaboutEntranceAngles,
                exitAngles: instruction.roundaboutExitAngles,
                activeExitAngle: instruction.roundaboutActiveExitAngle,
                drivingSide: instruction.drivingSide,
                color: appearance.routeCardArrowColor,
                thickness: appearance.routeCardArrowThickness,
                style: RoundaboutStyle(
                  roundaboutColor: appearance.roundaboutRingColor,
                  entranceColor: appearance.roundaboutEntranceColor,
                  mainExitColor: appearance.roundaboutMainExitColor,
                  secondaryExitColor: appearance.roundaboutSecondaryExitColor,
                  laneMarkColor: appearance.roundaboutLaneColor,
                  glowColor: appearance.roundaboutGlowColor,
                  roundaboutOpacity: appearance.roundaboutOpacity,
                  entranceOpacity: appearance.roundaboutEntranceOpacity,
                  mainExitOpacity: 1,
                  secondaryExitOpacity: appearance.roundaboutSecondaryOpacity,
                  laneMarkOpacity: appearance.roundaboutLaneOpacity,
                  glowOpacity: appearance.roundaboutGlowOpacity,
                  roadWidth: 8 + appearance.routeCardArrowThickness * 3,
                  ringWidth: 8 + appearance.routeCardArrowThickness * 3,
                  laneMarkWidth: 1.5,
                  arrowLength: 14 + appearance.routeCardArrowSize * 12,
                  arrowWidth: 8 + appearance.routeCardArrowSize * 8,
                  arrowThickness: appearance.routeCardArrowThickness,
                  arrowPosition: .72,
                  glowEnabled: appearance.roundaboutGlowOpacity > 0,
                ),
              )
            : ManeuverArrowIcon(
                modifier: instruction.modifier,
                color: appearance.routeCardArrowColor,
                thickness: appearance.routeCardArrowThickness,
              ),
        distanceText: dNext > 0 ? nextText : '',
        streetText: _compactRouteInstruction(instruction.text),
        etaLabel: AppStrings.get(context, ref, 'route_eta'),
        etaValue: etaText,
        remainingLabel: AppStrings.get(context, ref, 'route_remaining'),
        remainingValue: _formatRemainingDistance(
          context,
          ref,
          remainingKm * 1000.0,
        ),
        durationLabel: AppStrings.get(context, ref, 'route_time'),
        durationValue: AppStrings.getWithParams(
          context,
          ref,
          'route_duration_minutes',
          {'value': remainingMin},
        ),
        onClose: onClose,
        // پیکان معمولی باید مستقیماً از تنظیم «اندازه فلش» پیروی کند؛
        // برای میدان ۱ می‌ماند چون اندازهٔ حلقه و خروجی‌ها داخل style کنترل می‌شود.
        iconScale: isRoundabout
            ? 1.0
            : 0.7 + appearance.routeCardArrowSize * 0.6,
      ),
    );
  }

  String _compactRouteInstruction(String value) {
    var text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length <= 62) return text;

    // Prefer a natural semantic break before blindly cutting a street name.
    for (final marker in const [' - ', '، ', ' به ', ' در ']) {
      final idx = text.indexOf(marker, 28);
      if (idx >= 28 && idx <= 56) {
        final head = text.substring(0, idx).trim();
        if (head.length >= 24) return '$head…';
      }
    }
    return '${text.substring(0, 59).trimRight()}…';
  }

  String _formatRemainingDistance(
    BuildContext context,
    WidgetRef ref,
    double meters,
  ) {
    if (!meters.isFinite || meters < 0) return '--';
    if (meters < 1000) {
      return AppStrings.getWithParams(context, ref, 'route_distance_m', {
        'value': meters.round(),
      });
    }
    final km = meters / 1000.0;
    return AppStrings.getWithParams(context, ref, 'route_distance_km', {
      'value': km < 10 ? km.toStringAsFixed(1) : km.toStringAsFixed(0),
    });
  }

  IconData _getInstructionIcon(String type, String? modifier) {
    switch (type) {
      case 'turn':
      case 'uturn':
      case 'continue':
      case 'new name':
      case 'end of road':
        final m = (modifier ?? '')
            .toLowerCase()
            .replaceAll('-', ' ')
            .replaceAll('_', ' ');
        if (type == 'uturn' || m.contains('uturn') || m.contains('u turn')) {
          // U-turn has no meaningful left/right side at ~180°. Use the
          // dedicated left glyph only when the source explicitly supplies a
          // side; otherwise keep the maneuver class stable.
          return m.contains('right')
              ? Icons.u_turn_right_rounded
              : Icons.u_turn_left_rounded;
        }
        if (m.contains('sharp left')) return Icons.turn_sharp_left_rounded;
        if (m.contains('sharp right')) return Icons.turn_sharp_right_rounded;
        if (m.contains('slight left')) return Icons.turn_slight_left_rounded;
        if (m.contains('slight right')) return Icons.turn_slight_right_rounded;
        if (m.contains('left')) return Icons.turn_left_rounded;
        if (m.contains('right')) return Icons.turn_right_rounded;
        if (m.contains('straight')) return Icons.straight_rounded;
        return Icons.arrow_upward_rounded;
      case 'arrive':
        return Icons.flag_rounded;
      case 'depart':
        return Icons.navigation_rounded;
      case 'merge':
        return Icons.merge_rounded;
      case 'roundabout':
      case 'rotary':
        return Icons.roundabout_right_rounded;
      default:
        return Icons.arrow_upward_rounded;
    }
  }
}

/// هشدارهای جاده‌ای در یک نشانگر مربعیِ کوچک نمایش داده می‌شوند؛
/// طراحی دوربین و سرعت‌گیر مطابق نمونهٔ مرجع است.
class _RoadAlertIconOnly extends StatelessWidget {
  final RouteAlert alert;
  const _RoadAlertIconOnly({required this.alert});

  ({IconData icon, Color color}) get _visual {
    switch (alert.type) {
      case RouteAlertType.speedCamera:
        return (icon: Icons.videocam_rounded, color: const Color(0xFF34C6FF));
      case RouteAlertType.speedBump:
        return (
          icon: Icons.warning_amber_rounded,
          color: AppColors.secondaryAccent,
        );
      case RouteAlertType.policeCheckpoint:
        return (icon: Icons.local_police_rounded, color: AppColors.danger);
      case RouteAlertType.trafficLight:
        return (icon: Icons.traffic_rounded, color: const Color(0xFFFFD54F));
    }
  }

  @override
  Widget build(BuildContext context) {
    final visual = _visual;
    return Icon(
      visual.icon,
      color: visual.color,
      size: 38,
      shadows: [
        Shadow(color: Colors.black.withOpacity(.9), blurRadius: 7),
        Shadow(color: visual.color.withOpacity(.7), blurRadius: 12),
      ],
    );
  }
}
