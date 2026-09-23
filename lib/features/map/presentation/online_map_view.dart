import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;


import '../../../abtinmap/abm_models.dart';
import '../../../core/geo/geo_types.dart';
import '../../../shared/providers/map_style_providers.dart';
import '../../../world/world_countries.dart';
import '../../offline_maps/data/vector_map_service.dart';
import '../../gps/data/location_service.dart';
import '../../vehicle/presentation/nav_arrow_painter.dart';
import '../../vehicle/presentation/car_marker.dart';

/// زاویهٔ مکان‌نما نسبت به صفحه، بر پایهٔ heading جغرافیایی GPS و جهت فعلی
/// دوربین. خروجی در بازهٔ استاندارد ۰ تا کمتر از ۳۶۰ درجه است.
double mapRelativeHeading(double headingDeg, double mapBearingDeg) {
  final heading = headingDeg.isFinite ? headingDeg : 0.0;
  final bearing = mapBearingDeg.isFinite ? mapBearingDeg : 0.0;
  return (heading - bearing) % 360.0;
}

/// MapLibre Android موقعیت را با pixel فیزیکی View برمی‌گرداند، در حالی که
/// Positioned در Flutter با logical pixel کار می‌کند. بدون این تبدیل، marker
/// روی نمایشگرهای با تراکم بالاتر از ۱ به سمت لبهٔ پایین/راست جابه‌جا می‌شد.
const Map<int, List<String>> _offlinePoiClassesByKlass = {
  AbmKlass.poiFuel: ['fuel'],
  AbmKlass.poiParking: ['parking', 'bicycle_parking'],
  AbmKlass.poiHospital: ['hospital', 'clinic', 'doctors'],
  AbmKlass.poiPharmacy: ['pharmacy'],
  AbmKlass.poiPolice: ['police'],
  AbmKlass.poiSchool: ['school', 'college', 'university', 'kindergarten'],
  AbmKlass.poiRestaurant: ['restaurant', 'fast_food', 'food_court'],
  AbmKlass.poiCafe: ['cafe', 'ice_cream'],
  AbmKlass.poiBank: ['bank', 'atm'],
  AbmKlass.poiHotel: ['hotel', 'motel', 'hostel', 'guest_house', 'apartment'],
  AbmKlass.poiSupermarket: [
    'supermarket',
    'convenience',
    'department_store',
    'mall',
    'greengrocer',
  ],
  AbmKlass.poiMosque: ['place_of_worship'],
  AbmKlass.poiToilets: ['toilets'],
  AbmKlass.poiBusStation: ['bus_station', 'bus_stop'],
  AbmKlass.poiAirport: ['aerodrome', 'airport'],
  AbmKlass.poiAttraction: [
    'attraction',
    'museum',
    'viewpoint',
    'zoo',
    'theme_park',
    'monument',
    'memorial',
    'castle',
    'archaeological_site',
  ],
  AbmKlass.poiPark: ['park', 'garden', 'nature_reserve'],
  AbmKlass.poiPitch: ['pitch', 'sports_centre', 'stadium'],
  AbmKlass.poiPlace: [
    'city',
    'town',
    'village',
    'suburb',
    'neighbourhood',
    'quarter',
    'hamlet',
    'locality',
  ],
  AbmKlass.poiSpeedCamera: ['speed_camera'],
  AbmKlass.poiSpeedBump: ['bump', 'hump', 'table', 'cushion', 'chicane'],
  AbmKlass.poiTrafficLight: ['traffic_signals'],
};

List<dynamic> offlinePoiLayerFilter(Set<int>? visibleKlasses, {bool requireName = true}) {
  if (visibleKlasses != null && visibleKlasses.isEmpty) {
    return const <dynamic>[
      '==',
      ['get', 'class'],
      '__abtin-hidden-poi__'
    ];
  }
  final enabled = visibleKlasses ?? _offlinePoiClassesByKlass.keys.toSet();
  final classes = <String>{
    for (final klass in enabled) ...?_offlinePoiClassesByKlass[klass],
  }.toList(growable: false);
  // هر دو schema پشتیبانی می‌شود: class متنی در MVT یا klass عددی ABM.
  return <dynamic>[
    'all',
    if (requireName) ['has', 'name'],
    [
      'any',
      [
        'in',
        ['get', 'class'],
        ...classes
      ],
      [
        'in',
        ['get', 'klass'],
        ...enabled
      ],
    ],
  ];
}

bool sameOfflinePoiVisibility(Set<int>? a, Set<int>? b) {
  if (a == null || b == null) return a == null && b == null;
  return a.length == b.length && a.containsAll(b);
}


List<dynamic> onlinePoiLayerFilter(
  Set<int>? visibleKlasses, {
  required String layerId,
}) {
  final enabled = visibleKlasses ?? _offlinePoiClassesByKlass.keys.toSet();
  final classes = <String>{
    for (final klass in enabled) ...?_offlinePoiClassesByKlass[klass],
  }.toList(growable: false);

  if (layerId == 'poi_transit') {
    final transitClasses = classes.where((value) =>
        value == 'airport' || value == 'bus' || value == 'rail').toList(growable: false);
    if (transitClasses.isEmpty) {
      return const <dynamic>['==', ['get', 'class'], '__abtin-hidden-poi__'];
    }
    return <dynamic>['all',
      ['match', ['geometry-type'], ['MultiPoint', 'Point'], true, false],
      ['in', ['get', 'class'], ...transitClasses],
    ];
  }

  final rankFilter = switch (layerId) {
    'poi_r1' => <dynamic>['all',
      ['>=', ['get', 'rank'], 1],
      ['<', ['get', 'rank'], 7],
    ],
    'poi_r7' => <dynamic>['all',
      ['>=', ['get', 'rank'], 7],
      ['<', ['get', 'rank'], 20],
    ],
    _ => <dynamic>['>=', ['get', 'rank'], 20],
  };

  return <dynamic>[
    'all',
    ['match', ['geometry-type'], ['MultiPoint', 'Point'], true, false],
    rankFilter,
    if (classes.isEmpty)
      const <dynamic>['==', ['get', 'class'], '__abtin-hidden-poi__']
    else
      <dynamic>['in', ['get', 'class'], ...classes],
  ];
}

List<dynamic> roadWidthExpression(double scale, {double base = 1.0}) {
  final safeScale = scale.clamp(0.6, 1.8).toDouble();
  return <dynamic>[
    'interpolate',
    ['linear'],
    ['zoom'],
    6,
    base * safeScale,
    10,
    base * 1.35 * safeScale,
    14,
    base * 3.2 * safeScale,
    18,
    base * 8.0 * safeScale,
    20,
    base * 12.0 * safeScale,
  ];
}

Offset mapScreenPointToFlutterOffset(
  math.Point<dynamic> screenPoint,
  double devicePixelRatio,
) {
  final ratio = devicePixelRatio.isFinite && devicePixelRatio > 0
      ? devicePixelRatio
      : 1.0;
  return Offset(
    screenPoint.x.toDouble() / ratio,
    screenPoint.y.toDouble() / ratio,
  );
}

class OnlineRouteOverlay {
  const OnlineRouteOverlay({
    required this.geometry,
    required this.color,
    required this.width,
  });

  final List<LatLng> geometry;
  final Color color;
  final double width;
}

/// MapLibre Native نمایش نقشهٔ آنلاین را با همان renderer GPU نقشهٔ آفلاین
/// renderer برداری داخلی هم‌راستا نگه می‌دارد. دادهٔ route و خودرو از سرویس‌های محلی آبتین
/// می‌آید و به provider نقشه وابسته نیست.
class OnlineMapView extends StatefulWidget {
  const OnlineMapView({
    super.key,
    required this.vehiclePosition,
    required this.showCarModel,
    required this.modelIndex,
    required this.isDark,
    required this.followVehicle,
    required this.drivingMode,
    required this.markerColor,
    required this.pinSizePercent,
    required this.carSizePercent,
    required this.pinShadowEnabled,
    required this.cameraTiltDegrees,
    required this.carCameraAngleDegrees,
    required this.locationFocusRequest,
    required this.palette,
    required this.visiblePoiKlasses,
    this.localStylePath,
    this.abmFile,
    this.abmCountry,
    this.routeGeometry,
    this.routeOverlays,
    this.routeProgressMeters,
    this.routeColor = const Color(0xFF2FE6C4),
    this.routeWidth = 7.0,
    this.destination,
    this.onLongPress,
    this.onMapTap,
    this.onPoiTap,
    this.onRouteTap,
    this.onUserGestureStart,
    this.onCameraIdle,
    this.onCameraPositionChanged,
    this.onStyleLoaded,
  });

  /// null یعنی هنوز فیکس زنده و قابل اعتماد دریافت نشده است. در این حالت
  /// نقشه باز می‌ماند، اما marker و follow-camera عمداً فعال نمی‌شوند.
  final VehiclePosition? vehiclePosition;

  /// true یعنی مکان‌نمای سه‌بعدیِ خودرو نمایش داده شود؛ false یعنی فلشِ
  /// استانداردِ ناوبری (معادلِ AppearanceTab.car / AppearanceTab.pin).
  final bool showCarModel;
  final int modelIndex;
  final bool isDark;
  final bool followVehicle;
  final bool drivingMode;
  final Color markerColor;
  final double pinSizePercent;
  final double carSizePercent;
  final bool pinShadowEnabled;
  final double cameraTiltDegrees;

  /// زاویهٔ اختصاصیِ دوربینِ مدلِ سه‌بعدیِ خودرو (۰=از بالا، ۹۰=از پشتِ
  /// خودرو) — مستقل از [cameraTiltDegrees] که کجیِ خودِ نقشه است.
  final double carCameraAngleDegrees;
  final int locationFocusRequest;
  final OfflineMapPalette palette;

  /// null یعنی همهٔ دسته‌های POI، و set خالی یعنی همه پنهان هستند.
  final Set<int>? visiblePoiKlasses;

  /// آفلاین‌خوانی از اپ حذف شده است؛ این مقدار دیگر داده‌ای تولید نمی‌کند و
  /// null یعنی style آنلاینِ بدون API key استفاده شود.
  final String? localStylePath;

  /// فایل .abm نصب‌شده. آفلاین‌خوانی حذف شده است — این مقدار دیگر باز/پردازش
  /// نمی‌شود؛ فقط برای سازگاریِ امضای ویجت با فراخوان‌کننده نگه داشته شده.
  final File? abmFile;

  /// شناسهٔ کشور/منطقه، فقط برای نام‌گذاریِ پوشهٔ کش داخلی.
  final String? abmCountry;
  final List<LatLng>? routeGeometry;
  final List<OnlineRouteOverlay>? routeOverlays;
  /// Progress of the active navigation route in meters. When supplied, the
  /// renderer keeps the traveled and remaining portions visually distinct.
  final double? routeProgressMeters;
  final Color routeColor;
  final double routeWidth;
  final LatLng? destination;
  final ValueChanged<LatLng>? onLongPress;
  final void Function(LatLng, Map<String, dynamic>)? onMapTap;
  final ValueChanged<Map<String, dynamic>>? onPoiTap;
  final ValueChanged<int>? onRouteTap;
  final VoidCallback? onUserGestureStart;
  final VoidCallback? onCameraIdle;
  final ValueChanged<ml.CameraPosition>? onCameraPositionChanged;
  final VoidCallback? onStyleLoaded;

  @override
  State<OnlineMapView> createState() => _OnlineMapViewState();
}

class _OnlineMapViewState extends State<OnlineMapView> {
  // Camera follow must never queue long animations. A 220ms animation
  // triggered every 100ms made the camera permanently lag behind the car.
  static const _cameraUpdateInterval = Duration(milliseconds: 50);
  // No country/city is hardcoded. Until GPS or the active-map bbox is known,
  // MapLibre starts from a neutral world view; the active ABM bbox is applied
  // only as a map-data fallback, never as the user's location.
  static const _fallbackInitialTarget = ml.LatLng(0.0, 0.0);

  ml.MapLibreMapController? _controller;
  ml.CameraPosition? _camera;
  Offset? _vehicleScreen;
  Offset? _destinationScreen;
  bool _styleReady = false;
  bool _onlineStreetLabelsAdded = false;
  bool _onlinePoiLabelsAdded = false;
  bool _onlinePoiDotsAdded = false;
  bool _onlineRoadDirectionsAdded = false;
  bool _screenUpdateRunning = false;
  bool _screenUpdateQueued = false;
  int _screenUpdateGeneration = 0;
  bool _cameraMoveRunning = false;
  ml.CameraPosition? _pendingCameraPosition;
  DateTime _lastCameraUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _lastCameraBearingAt;
  double? _smoothedCameraBearing;
  final List<ml.Line> _routeLines = <ml.Line>[];
  int _routeRefreshGeneration = 0;
  int _pendingLocationFocusRequest = 0;

  // کشِ پیشرفتِ خودرو روی route.geometry برای هدفِ دوربینِ ناوبری (نگاه کنید
  // به _pointAheadOnRoute). جدا از کشِ مشابه در home_screen است چون این
  // ویجت مستقلاً به geometry دسترسی دارد.
  List<LatLng>? _navRouteGeometry;
  List<double>? _navRouteCumulativeM;
  int? _navRouteLastSegment;

  // --- Offline ABM rendering -----------------------------------------
  // The renderer consumes the builder's ABMV1 spatial chunks directly. Only
  // chunks intersecting the current viewport are extracted/parsed.
  Timer? _abmRefreshTimer;
  bool _worldLayerLoaded = false;
  bool _abmRefreshRunning = false;
  bool _abmRefreshQueued = false;
  int _abmRefreshGeneration = 0;
  final VectorMapService _vectorMapService = VectorMapService();
  // The un-padded camera bounds used for the last successful ABM viewport
  // load. `_refreshAbmViewport` always fetches this box expanded by 20% on
  // every side (see `sideFraction` below), so as long as the GPS fix stays
  // inside `_loadedAbmCoreBounds` the already-loaded data still fully
  // covers the padded viewport and a reload would be wasted work (a new
  // isolate + sqlite query on every single GPS tick). Only once the fix
  // crosses out of this box -- i.e. it has reached the 20% padding band --
  // is a fresh, bbox-scoped reload actually needed.
  AbmBBox? _loadedAbmCoreBounds;

  // MapLibre location puck is intentionally disabled. The app uses its own
  // navigation vehicle marker and must not show the default blue location dot.

  static const double _minMapZoom = 2.0;
  // 18 per user request: allow closer street-level inspection. The offline
  // ABM files use overview zooms so 17–18 fall back to lower-resolution
  // overview tiles rather than showing blank voids.
  static const double _maxMapZoom = 18.0;

  ml.LatLng _toMapLibrePoint(LatLng point) =>
      ml.LatLng(point.latitude, point.longitude);

  ml.LatLng _toMapLibreVehiclePoint(VehiclePosition point) =>
      ml.LatLng(point.lat, point.lng);

  List<OnlineRouteOverlay> get _routeOverlays =>
      widget.routeOverlays ?? _buildActiveRouteOverlays();

  List<OnlineRouteOverlay> _buildActiveRouteOverlays() {
    final geometry = widget.routeGeometry;
    if (geometry == null || geometry.length < 2) {
      return const <OnlineRouteOverlay>[];
    }
    final progress = widget.routeProgressMeters;
    if (progress == null || !progress.isFinite || progress <= 0) {
      return <OnlineRouteOverlay>[
        OnlineRouteOverlay(
          geometry: geometry,
          color: widget.routeColor,
          width: widget.routeWidth,
        ),
      ];
    }
    if (progress >= _polylineLengthMeters(geometry)) {
      return <OnlineRouteOverlay>[
        OnlineRouteOverlay(
          geometry: geometry,
          color: widget.routeColor.withValues(alpha: 0.45),
          width: widget.routeWidth,
        ),
      ];
    }

    final traveled = <LatLng>[];
    final remaining = <LatLng>[];
    var accumulated = 0.0;
    var splitDone = false;
    for (var i = 0; i < geometry.length - 1; i++) {
      final a = geometry[i];
      final b = geometry[i + 1];
      final segment = _polylineSegmentMeters(a, b);
      if (!splitDone && accumulated + segment >= progress && segment > 0.01) {
        final t = ((progress - accumulated) / segment).clamp(0.0, 1.0);
        final split = LatLng(
          a.latitude + (b.latitude - a.latitude) * t,
          a.longitude + (b.longitude - a.longitude) * t,
        );
        if (traveled.isEmpty) traveled.add(a);
        traveled.add(split);
        remaining.add(split);
        remaining.add(b);
        splitDone = true;
      } else if (!splitDone) {
        if (traveled.isEmpty) traveled.add(a);
        traveled.add(b);
      } else {
        remaining.add(b);
      }
      accumulated += segment;
    }

    final overlays = <OnlineRouteOverlay>[];
    if (traveled.length >= 2) {
      overlays.add(OnlineRouteOverlay(
        geometry: traveled,
        color: widget.routeColor.withValues(alpha: 0.38),
        width: widget.routeWidth,
      ));
    }
    if (remaining.length >= 2) {
      overlays.add(OnlineRouteOverlay(
        geometry: remaining,
        color: widget.routeColor,
        width: widget.routeWidth,
      ));
    }
    return overlays;
  }

  double _polylineSegmentMeters(LatLng a, LatLng b) {
    final latRad = ((a.latitude + b.latitude) / 2) * math.pi / 180.0;
    final mx = 111320.0 * math.cos(latRad);
    const my = 110540.0;
    final dx = (b.longitude - a.longitude) * mx;
    final dy = (b.latitude - a.latitude) * my;
    return math.sqrt(dx * dx + dy * dy);
  }

  double _polylineLengthMeters(List<LatLng> geometry) {
    var total = 0.0;
    for (var i = 1; i < geometry.length; i++) {
      total += _polylineSegmentMeters(geometry[i - 1], geometry[i]);
    }
    return total;
  }

  @override
  void initState() {
    super.initState();
    _pendingLocationFocusRequest = widget.locationFocusRequest;
  }

  @override
  void dispose() {
    _abmRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant OnlineMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.abmFile?.path != widget.abmFile?.path) {
      // A different .abm file covers different ground entirely, so any
      // previously-loaded box is meaningless for it.
      _loadedAbmCoreBounds = null;
      _scheduleAbmRefresh(immediate: true);
    }
    final previousPosition = oldWidget.vehiclePosition;
    final nextPosition = widget.vehiclePosition;
    final positionChanged = previousPosition?.lat != nextPosition?.lat ||
        previousPosition?.lng != nextPosition?.lng ||
        previousPosition?.headingDeg != nextPosition?.headingDeg ||
        previousPosition?.speedKmh != nextPosition?.speedKmh;
    final tiltChanged = oldWidget.cameraTiltDegrees != widget.cameraTiltDegrees;
    final poiVisibilityChanged = !sameOfflinePoiVisibility(
      oldWidget.visiblePoiKlasses,
      widget.visiblePoiKlasses,
    );
    final routeProgressChanged =
        (oldWidget.routeProgressMeters == null) != (widget.routeProgressMeters == null) ||
        (oldWidget.routeProgressMeters != null &&
            widget.routeProgressMeters != null &&
            (oldWidget.routeProgressMeters! - widget.routeProgressMeters!).abs() >= 4.0);
    final routesChanged = oldWidget.routeOverlays != widget.routeOverlays ||
        oldWidget.routeGeometry != widget.routeGeometry ||
        oldWidget.routeColor != widget.routeColor ||
        oldWidget.routeWidth != widget.routeWidth ||
        routeProgressChanged;

    if (oldWidget.locationFocusRequest != widget.locationFocusRequest) {
      _pendingLocationFocusRequest = widget.locationFocusRequest;
      _focusGpsCamera();
    }
    if (oldWidget.destination != widget.destination &&
        widget.destination != null) {
      _focusDestination(widget.destination!);
    }
    // Follow-camera is a map behavior, not a navigation-only behavior.
    // When the user has not manually taken control, the camera must stay
    // behind the vehicle both with and without an active route.
    if (widget.followVehicle &&
        nextPosition != null &&
        (positionChanged ||
            tiltChanged ||
            oldWidget.followVehicle != widget.followVehicle ||
            oldWidget.drivingMode != widget.drivingMode)) {
      _syncCamera(force: tiltChanged);
    } else if (tiltChanged && !widget.followVehicle) {
      final controller = _controller;
      if (controller != null) {
        unawaited(
          controller.animateCamera(
            ml.CameraUpdate.tiltTo(widget.cameraTiltDegrees.clamp(0, 60)),
            duration: const Duration(milliseconds: 220),
          ),
        );
      }
    }
    if (_styleReady && poiVisibilityChanged) {
      unawaited(_applyPoiVisibility());
    }
    if (_styleReady && routesChanged) {
      unawaited(_refreshRouteAnnotations());
    }
    if (positionChanged || oldWidget.destination != widget.destination) {
      if (positionChanged && widget.abmFile != null && nextPosition != null) {
        // NOTE: this used to also call `_focusGpsCamera()` here on every
        // single GPS tick. `_focusGpsCamera` does an instant, unanimated
        // `moveCamera` -- meant only for one-off re-anchors like the GPS
        // button (see `locationFocusRequest` above) or first load. Calling
        // it on every tick raced with the smooth `_syncCamera` animation
        // started a few lines above for the very same tick: the animation
        // would begin, then immediately get hard-cut to (almost) the same
        // target, which is exactly the jarring "snap" visible in the
        // recording. `_syncCamera` already re-centers the camera smoothly
        // whenever `followVehicle` is on, for both online and offline, so
        // this block only needs to decide whether the ABM data still
        // covers the new position.
        if (_needsAbmReload(nextPosition.lat, nextPosition.lng)) {
          _scheduleAbmRefresh(immediate: true);
        }
      }
      unawaited(_refreshScreenPositions());
    }
  }

  ml.CameraPosition _computeInitialCameraPosition() {
    return ml.CameraPosition(
      target: widget.vehiclePosition == null
          ? _fallbackInitialTarget
          : _toMapLibreVehiclePoint(widget.vehiclePosition!),
      zoom: widget.vehiclePosition == null
          ? 1.0
          : (widget.drivingMode ? 16 : 14.5),
      bearing: widget.vehiclePosition?.headingDeg ?? 0,
      tilt: widget.drivingMode
          ? widget.cameraTiltDegrees.clamp(42.0, 55.0).toDouble()
          : widget.cameraTiltDegrees.clamp(0.0, 60.0).toDouble(),
    );
  }

  void _onMapCreated(ml.MapLibreMapController controller) {
    _controller = controller;
    // Initialize the camera before the first ABM viewport query. MapLibre can
    // report its constructor camera (often 0,0) for a short window while the
    // real GPS camera is being applied. Starting the ABM query during that
    // window produces a perfectly valid but completely empty viewport.
    unawaited(_initializeMapCamera(controller));
  }

  Future<void> _initializeMapCamera(ml.MapLibreMapController controller) async {
    if (!mounted || controller != _controller) return;
    final gps = widget.vehiclePosition;
    _camera = _computeInitialCameraPosition();
    try {
      if (gps != null) {
        final zoom = widget.drivingMode
            ? _navigationZoom(gps.speedKmh)
            : _maxMapZoom;
        final target = widget.drivingMode
            ? _navigationCameraTarget(gps, zoom)
            : _toMapLibreVehiclePoint(gps);
        final position = ml.CameraPosition(
          target: target,
          zoom: zoom,
          bearing: widget.drivingMode ? gps.headingDeg : 0,
          tilt: widget.drivingMode
              ? widget.cameraTiltDegrees.clamp(42.0, 55.0).toDouble()
              : 0,
        );
        _camera = position;
        await controller.moveCamera(ml.CameraUpdate.newCameraPosition(position));
      } else if (widget.abmFile != null) {
        await _centerOnOfflineMapBounds(controller);
      }
    } catch (e, st) {
      
    }
    if (!mounted || controller != _controller) return;
    // Do not wait for a user gesture. The first data request is explicitly
    // tied to the camera we just established. onStyleLoaded will also trigger
    // this path, but the generation guard prevents stale results.
    if (_styleReady && widget.abmFile != null) {
      _scheduleAbmRefresh(immediate: true);
    }
    _focusGpsCamera();
  }

  Future<void> _centerOnOfflineMapBounds(ml.MapLibreMapController controller) async {
    try {
      final file = widget.abmFile;
      if (file == null || !await file.exists()) return;
      // If GPS arrived between onMapCreated and this async metadata read, GPS
      // is authoritative (e.g. the user is in Arak while AM.abm is also
      // installed). Never replace a valid GPS position with the file center.
      if (widget.vehiclePosition != null) {
        _focusGpsCamera();
        return;
      }
      final id = widget.abmCountry?.isNotEmpty == true
          ? widget.abmCountry!
          : p.basenameWithoutExtension(file.path);
      final artifacts = await _vectorMapService.prepare(
        containerFile: file,
        id: id,
      );
      final raw = artifacts.metadata['bbox'];
      if (raw is List && raw.length >= 4) {
        final minLon = (raw[0] as num).toDouble();
        final minLat = (raw[1] as num).toDouble();
        final maxLon = (raw[2] as num).toDouble();
        final maxLat = (raw[3] as num).toDouble();
        await controller.moveCamera(ml.CameraUpdate.newLatLngBounds(
          ml.LatLngBounds(
            southwest: ml.LatLng(minLat, minLon),
            northeast: ml.LatLng(maxLat, maxLon),
          ),
          left: 32, right: 32, top: 32, bottom: 32,
        ));
        _camera = ml.CameraPosition(
          target: ml.LatLng((minLat + maxLat) / 2, (minLon + maxLon) / 2),
          zoom: 6, bearing: 0, tilt: 0,
        );
      }
    } catch (e, st) {
      
    }
  }

  Future<void> _applyPoiVisibility() async {
    final c = _controller;
    if (c == null || !_styleReady) return;
    try {
      if (widget.localStylePath != null) {
        await c.setFilter('poi-points', offlinePoiLayerFilter(widget.visiblePoiKlasses, requireName: false));
        await c.setFilter('poi-labels', offlinePoiLayerFilter(widget.visiblePoiKlasses));
      } else {
        // Online OpenMapTiles POIs are split by rank in the real style. Keep
        // each layer's original rank/geometry semantics while adding the
        // user's category filter; no synthetic POIs or provider-side query
        // results are created here.
        for (final layer in const ['poi_r1', 'poi_r7', 'poi_r20', 'poi_transit']) {
          await c.setFilter(
            layer,
            onlinePoiLayerFilter(
              widget.visiblePoiKlasses,
              layerId: layer,
            ),
          );
        }
      }
    } catch (e) {
      
    }
  }

  static const Map<String, String> _offlineSourceByLayer = {
    'places': 'abm-places',
    'poi': 'abm-poi',
    'roads': 'abm-roads',
  };

  Future<void> _loadWorldCountriesLayer() async {
    if (_worldLayerLoaded) return;
    final controller = _controller;
    if (controller == null) return;
    try {
      final world = await WorldCountries.load();
      if (!mounted || controller != _controller) return;
      await controller.setGeoJsonSource('world-countries', world);
      _worldLayerLoaded = true;
    } catch (error) {
      
    }
  }

  /// True when `position` has left the box that was actually loaded (the
  /// last visible camera bounds, before the 20% padding was added) -- i.e.
  /// it has reached the padding band and the padded data around it can no
  /// longer be assumed to still cover the viewport. False means the fix is
  /// still comfortably inside already-loaded data and no reload is needed.
  bool _needsAbmReload(double lat, double lng) {
    final core = _loadedAbmCoreBounds;
    if (core == null) return true;
    return lng < core.minLon || lng > core.maxLon ||
        lat < core.minLat || lat > core.maxLat;
  }

  void _scheduleAbmRefresh({bool immediate = false}) {
    if (widget.localStylePath == null || widget.abmFile == null || !_styleReady) return;
    _abmRefreshTimer?.cancel();
    if (immediate) {
      unawaited(_refreshAbmViewport());
      return;
    }
    _abmRefreshTimer = Timer(const Duration(milliseconds: 120), () {
      unawaited(_refreshAbmViewport());
    });
  }

  Future<void> _refreshAbmViewport() async {
    final controller = _controller;
    final file = widget.abmFile;
    if (controller == null || file == null || !_styleReady || !mounted) return;
    if (_abmRefreshRunning) {
      _abmRefreshQueued = true;
      return;
    }
    _abmRefreshRunning = true;
    final generation = ++_abmRefreshGeneration;
    try {
      final bounds = await controller.getVisibleRegion();
      final zoom = _camera?.zoom ?? 14.0;
      // Preload a 40% larger viewport so fast panning/zooming does not
      // expose empty edges while the next ABM chunks are being decoded.
      // 40% total expansion = 20% extra on each side.
      const preloadFraction = 0.40;
      const sideFraction = preloadFraction / 2.0;
      final minLon = bounds.southwest.longitude;
      final maxLon = bounds.northeast.longitude;
      final minLat = bounds.southwest.latitude;
      final maxLat = bounds.northeast.latitude;
      final lonSpan = (maxLon - minLon).abs();
      final latSpan = (maxLat - minLat).abs();
      final expandedMinLon = minLon - lonSpan * sideFraction;
      final expandedMaxLon = maxLon + lonSpan * sideFraction;
      final expandedMinLat = (minLat - latSpan * sideFraction).clamp(-85.05112878, 85.05112878);
      final expandedMaxLat = (maxLat + latSpan * sideFraction).clamp(-85.05112878, 85.05112878);
      final bbox = AbmBBox(
        expandedMinLon,
        expandedMinLat.toDouble(),
        expandedMaxLon,
        expandedMaxLat.toDouble(),
      );
      final gps = widget.vehiclePosition;
      if (gps != null &&
          (gps.lng < bbox.minLon || gps.lng > bbox.maxLon ||
              gps.lat < bbox.minLat || gps.lat > bbox.maxLat)) {
        
      }
      final centerLat = (bbox.minLat + bbox.maxLat) / 2;
      final centerLon = (bbox.minLon + bbox.maxLon) / 2;
      
      final layers = await _vectorMapService.loadViewport(
        containerFile: file, bbox: bbox, zoom: zoom,
      );
      // The offline viewport is read directly from map.sqlite; there is no
      // tile probe or secondary tile database in the render path.
      if (!mounted || generation != _abmRefreshGeneration || controller != _controller) return;
      
      for (final entry in _offlineSourceByLayer.entries) {
        final data = layers[entry.key];
        final geojson = data == null
            ? const <String, dynamic>{'type': 'FeatureCollection', 'features': <dynamic>[]}
            : <String, dynamic>{
                'type': 'FeatureCollection',
                'features': data.map((f) => f.toGeoJson()).toList(growable: false),
              };
        await controller.setGeoJsonSource(entry.value, geojson);
      }
      // Record the un-padded box this load actually covers (with its 20%
      // margin) so the next GPS fix can be checked against it before
      // deciding whether another reload is warranted at all.
      _loadedAbmCoreBounds = AbmBBox(minLon, minLat, maxLon, maxLat);
    } catch (error, stack) {
      
    } finally {
      _abmRefreshRunning = false;
      if (_abmRefreshQueued && mounted) {
        _abmRefreshQueued = false;
        _scheduleAbmRefresh();
      }
    }
  }

  void _onStyleLoaded() {
    _styleReady = true;
    _routeLines.clear();
    _onlineStreetLabelsAdded = false;
    _onlinePoiLabelsAdded = false;
    _onlinePoiDotsAdded = false;
    _onlineRoadDirectionsAdded = false;
    _worldLayerLoaded = false;
    // A reloaded style starts with empty abm-* GeoJSON sources again, so any
    // previously-loaded box no longer describes what's actually on screen.
    _loadedAbmCoreBounds = null;
    // The online provider style is the single source of visual truth. Do not
    // rewrite its paint values here: doing so used to make offline landuse
    // green while online stayed on the OpenFreeMap palette.
    // Online POI, street labels and one-way arrows are part of the bundled
    // unified style. Their data remains OpenMapTiles/network data; the icon
    // atlas and glyphs are local project assets. Do not mutate the style here.
    if (widget.localStylePath != null) {
      unawaited(_applyPoiVisibility());
      unawaited(_loadWorldCountriesLayer());
      _scheduleAbmRefresh(immediate: true);
    }
    widget.onStyleLoaded?.call();
    unawaited(_refreshRouteAnnotations());
    if (_pendingLocationFocusRequest != 0) {
      _focusGpsCamera();
    } else if (widget.drivingMode && widget.vehiclePosition != null) {
      _syncCamera(force: true);
    } else {
      unawaited(_refreshScreenPositions());
    }
  }

  /// The OpenFreeMap online style is the single visual source of truth.
  /// Palette settings remain part of the public map API for compatibility,
  /// but no longer mutate the style differently between online/offline modes.
  Future<void> _applyMapPalette() async {}

  Future<void> _refreshRouteAnnotations() async {
    final controller = _controller;
    if (!_styleReady || controller == null) return;
    final generation = ++_routeRefreshGeneration;
    final routes = _routeOverlays
        .where((route) => route.geometry.length >= 2)
        .toList(growable: false);
    final options = <ml.LineOptions>[
      for (final route in routes)
        ml.LineOptions(
          geometry:
              route.geometry.map(_toMapLibrePoint).toList(growable: false),
          lineColor: _hexColor(route.color),
          lineWidth: route.width,
          lineOpacity: 1,
          lineJoin: 'round',
        ),
    ];
    try {
      // در لغو مسیر، حذف را مستقیم و قطعی انجام می‌دهیم. مسیرهای پیشنهادی
      // قبلی ممکن است هم‌زمان با تغییر provider در یک frame باقی مانده باشند؛
      // جایگزینی با لیست خالی نباید منتظر addLines بماند.
      if (options.isEmpty) {
        final previous = List<ml.Line>.from(_routeLines);
        _routeLines.clear();
        if (previous.isNotEmpty) await controller.removeLines(previous);
        return;
      }

      if (_routeLines.length == options.length) {
        for (var index = 0; index < options.length; index++) {
          if (generation != _routeRefreshGeneration) return;
          await controller.updateLine(_routeLines[index], options[index]);
        }
        return;
      }

      // خطوط تازه ابتدا اضافه می‌شوند و فقط پس از موفقیت، خطوط قبلی حذف
      // می‌گردند؛ بنابراین با انتخاب route جدید نقشه حتی یک frame بدون مسیر
      // نمی‌ماند و flicker رخ نمی‌دهد.
      final replacement = options.isEmpty
          ? const <ml.Line>[]
          : await controller.addLines(options);
      if (generation != _routeRefreshGeneration || controller != _controller) {
        if (replacement.isNotEmpty) await controller.removeLines(replacement);
        return;
      }
      final previous = List<ml.Line>.from(_routeLines);
      _routeLines
        ..clear()
        ..addAll(replacement);
      if (previous.isNotEmpty) await controller.removeLines(previous);
    } catch (_) {
      // در لحظهٔ جایگزینی style، annotation manager قدیمی ممکن است آزاد شده
      // باشد. callback بارگذاری style، خطوط route را دوباره ثبت می‌کند.
    }
  }

  String _hexColor(Color color) {
    final argb = color.toARGB32();
    return '#${((argb >> 16) & 0xFF).toRadixString(16).padLeft(2, '0')}${((argb >> 8) & 0xFF).toRadixString(16).padLeft(2, '0')}${(argb & 0xFF).toRadixString(16).padLeft(2, '0')}';
  }

  void _focusGpsCamera() {
    final controller = _controller;
    final position = widget.vehiclePosition;
    if (controller == null || position == null) return;
    _pendingLocationFocusRequest = 0;
    // GPS button is a re-anchor, not a queued animation. First put the map
    // exactly on the current vehicle frame; the next follow tick takes over.
    final zoom =
        widget.drivingMode ? _navigationZoom(position.speedKmh) : _maxMapZoom;
    // In navigation the vehicle is intentionally rendered around 64% down
    // the viewport. Re-anchoring the GPS button must use the same camera
    // target, otherwise the marker briefly jumps to the center and then back
    // to the lower-third follow position.
    final target = widget.drivingMode
        ? _navigationCameraTarget(position, zoom)
        : _toMapLibreVehiclePoint(position);
    unawaited(controller.moveCamera(
      ml.CameraUpdate.newCameraPosition(
        ml.CameraPosition(
          target: target,
          zoom: zoom,
          bearing: widget.drivingMode ? position.headingDeg : 0,
          tilt: widget.drivingMode
              ? widget.cameraTiltDegrees.clamp(42.0, 55.0).toDouble()
              : 0,
        ),
      ),
    ));
  }

  void _focusDestination(LatLng destination) {
    final controller = _controller;
    if (controller == null) return;
    unawaited(
      controller.animateCamera(
        ml.CameraUpdate.newCameraPosition(
          ml.CameraPosition(
            target: _toMapLibrePoint(destination),
            zoom: (_maxMapZoom - 1).clamp(14.0, _maxMapZoom),
            bearing: 0,
            tilt: 0,
          ),
        ),
        duration: const Duration(milliseconds: 320),
      ),
    );
  }

  /// در ناوبری، خودرو نباید وسط صفحه قفل شود؛ باید در نیمهٔ پایین بماند
  /// و بخش بیشتری از مسیرِ جلوی راننده دیده شود، شبیه Google Maps/Waze.
  /// بنابراین مرکز دوربین چند ده متر در امتداد heading جلوتر از خودرو قرار
  /// می‌گیرد. این کار با tilt نیز پایدارتر از دستکاریِ مختصاتِ screen است.
  ml.LatLng _navigationCameraTarget(
    VehiclePosition position,
    double zoom,
  ) {
    // فاصلهٔ جلو با zoom کمی تغییر می‌کند تا در زوم نزدیک خودرو خیلی پایین
    // نیفتد و در سرعت بالا مسیرِ بیشتری در جلو قابل مشاهده باشد.
    // دوربین قبلاً 65 تا 100 متر جلوتر از خودرو قفل می‌شد. در نمای شیب‌دار
    // این مقدار خودرو را بیش از حد به پایین صفحه می‌برد و گاهی زیر لایه‌های
    // HUD قرار می‌داد. هدف باید فقط کمی جلوتر از خودرو باشد تا خودِ خودرو
    // همیشه داخل viewport و نزدیک یک‌سوم پایینی صفحه دیده شود.
    final forwardMeters = (18.0 +
            (17.8 - zoom) * 2.5 +
            position.speedKmh.clamp(0.0, 100.0) * 0.05)
        .clamp(14.0, 28.0)
        .toDouble();

    // در حالت ناوبری، هدف دوربین کمی جلوتر از موقعیت واقعی خودرو قرار
    // می‌گیرد تا بخش بیشتری از مسیر جلوی راننده دیده شود. خودِ خودرو دیگر
    // مختصات ثابتِ صفحه‌ای ندارد؛ موقعیت جغرافیایی animated آن مستقیماً به
    // screen projection تبدیل می‌شود، بنابراین همیشه روی همان route می‌نشیند.
    // قبلاً هدف با امتداد خط‌راستِ heading فعلی محاسبه می‌شد؛ توی پیچ‌ها
    // این خط‌راست، وترِ پیچ را می‌برید نه کمانش را، پس دوربین از مسیرِ واقعی
    // جدا می‌افتاد. حالا وقتی geometry مسیر در دسترس است، هدف با پیمایشِ
    // forwardMeters روی خودِ همان geometry به دست می‌آید تا کمانِ پیچ را
    // دنبال کند، نه وترش را.
    final route = widget.routeGeometry;
    if (route != null && route.length >= 2) {
      final ahead = _pointAheadOnRoute(
        LatLng(position.lat, position.lng),
        route,
        forwardMeters,
      );
      if (ahead != null) return _toMapLibrePoint(ahead);
    }

    // Fallback (بدون مسیر فعال، یا وقتی خودرو خیلی از geometry دور است):
    // امتدادِ خط‌راستِ heading، مثل قبل.
    final heading = (position.headingDeg.isFinite ? position.headingDeg : 0.0) *
        math.pi /
        180.0;
    const metersPerLatitude = 110540.0;
    final lat =
        position.lat + (math.cos(heading) * forwardMeters) / metersPerLatitude;
    final cosLat =
        math.cos(position.lat * math.pi / 180.0).abs().clamp(0.15, 1.0);
    final metersPerLongitude = 111320.0 * cosLat;
    final lng =
        position.lng + (math.sin(heading) * forwardMeters) / metersPerLongitude;
    return ml.LatLng(lat, lng);
  }

  /// نقطه‌ای [forwardMeters] جلوتر از [position] روی خودِ [geometry] (نه خط‌راستِ
  /// heading). ابتدا [position] روی نزدیک‌ترین قطعه projection می‌شود تا
  /// پیشرفتِ فعلی (متر از ابتدای مسیر) به دست آید، سپس همان مقدار جلوتر روی
  /// geometry پیمایش می‌شود. جست‌وجو حول آخرین قطعهٔ منطبق‌شده پنجره‌ای است
  /// (مثل _matchPositionToRoute در home_screen) تا برای مسیرهای طولانی هر
  /// فریم O(کل مسیر) نشود؛ اگر نتیجهٔ پنجره خیلی دور بود، یک‌بار کل مسیر را
  /// جست‌وجو می‌کند.
  LatLng? _pointAheadOnRoute(
    LatLng position,
    List<LatLng> geometry,
    double forwardMeters,
  ) {
    if (geometry.length < 2) return null;
    if (!identical(_navRouteGeometry, geometry)) {
      _navRouteGeometry = geometry;
      _navRouteCumulativeM = _buildCumulativeDistancesM(geometry);
      _navRouteLastSegment = null;
    }
    final cumulative = _navRouteCumulativeM!;
    final lastSegmentCount = geometry.length - 2;

    const backWindowM = 60.0;
    const aheadWindowM = 300.0;
    var startIdx = 0;
    var endIdx = lastSegmentCount;
    final lastIdx = _navRouteLastSegment;
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

    var match = _bestRouteSegment(position, geometry, startIdx, endIdx);
    if (match.distanceMeters > 45 &&
        (startIdx > 0 || endIdx < lastSegmentCount)) {
      match = _bestRouteSegment(position, geometry, 0, lastSegmentCount);
    }
    if (match.distanceMeters > 80) {
      // خودرو خیلی از این geometry دور است (مثلاً هنوز به مسیر نرسیده)؛
      // امتدادِ خط‌راستِ heading قابل‌اعتمادتر از چسباندنِ زوری به مسیر است.
      return null;
    }

    _navRouteLastSegment = match.segmentIndex;
    final segLen =
        cumulative[match.segmentIndex + 1] - cumulative[match.segmentIndex];
    final progressM = cumulative[match.segmentIndex] + segLen * match.t;
    return _pointAtRouteDistanceM(
        geometry, cumulative, progressM + forwardMeters);
  }

  ({int segmentIndex, double t, double distanceMeters}) _bestRouteSegment(
    LatLng position,
    List<LatLng> geometry,
    int startIdx,
    int endIdx,
  ) {
    var bestDistance = double.infinity;
    var bestIndex = startIdx;
    var bestT = 0.0;
    for (var i = startIdx; i <= endIdx; i++) {
      final projection =
          _projectOnRouteSegment(position, geometry[i], geometry[i + 1]);
      if (projection.distanceMeters < bestDistance) {
        bestDistance = projection.distanceMeters;
        bestIndex = i;
        bestT = projection.t;
      }
    }
    return (segmentIndex: bestIndex, t: bestT, distanceMeters: bestDistance);
  }

  ({double distanceMeters, double t}) _projectOnRouteSegment(
    LatLng point,
    LatLng a,
    LatLng b,
  ) {
    final latRad = point.latitude * math.pi / 180.0;
    final mx = 111320.0 * math.cos(latRad);
    const my = 110540.0;
    final abX = (b.longitude - a.longitude) * mx;
    final abY = (b.latitude - a.latitude) * my;
    final apX = (point.longitude - a.longitude) * mx;
    final apY = (point.latitude - a.latitude) * my;
    final lengthSquared = abX * abX + abY * abY;
    if (lengthSquared <= 1e-6) {
      return (distanceMeters: math.sqrt(apX * apX + apY * apY), t: 0.0);
    }
    final t = ((apX * abX + apY * abY) / lengthSquared).clamp(0.0, 1.0);
    final nearestX = abX * t;
    final nearestY = abY * t;
    final dx = apX - nearestX;
    final dy = apY - nearestY;
    return (distanceMeters: math.sqrt(dx * dx + dy * dy), t: t);
  }

  List<double> _buildCumulativeDistancesM(List<LatLng> geometry) {
    final cumulative = List<double>.filled(geometry.length, 0);
    for (var i = 1; i < geometry.length; i++) {
      cumulative[i] =
          cumulative[i - 1] + _distanceBetweenM(geometry[i - 1], geometry[i]);
    }
    return cumulative;
  }

  LatLng _pointAtRouteDistanceM(
    List<LatLng> geometry,
    List<double> cumulative,
    double meters,
  ) {
    final total = cumulative.last;
    final target = meters.clamp(0.0, total);
    var lo = 0;
    var hi = cumulative.length - 1;
    while (lo < hi - 1) {
      final mid = (lo + hi) >> 1;
      if (cumulative[mid] <= target) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final a = geometry[lo];
    final b = geometry[hi];
    final segLen = cumulative[hi] - cumulative[lo];
    final t = segLen <= 0.0001
        ? 0.0
        : ((target - cumulative[lo]) / segLen).clamp(0.0, 1.0);
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  double _distanceBetweenM(LatLng a, LatLng b) {
    final latRad = ((a.latitude + b.latitude) / 2) * math.pi / 180.0;
    final mx = 111320.0 * math.cos(latRad);
    const my = 110540.0;
    final dx = (b.longitude - a.longitude) * mx;
    final dy = (b.latitude - a.latitude) * my;
    return math.sqrt(dx * dx + dy * dy);
  }

  void _syncCamera({bool force = false}) {
    final controller = _controller;
    final position = widget.vehiclePosition;
    if (controller == null || position == null || !widget.followVehicle) {
      return;
    }
    final now = DateTime.now();
    if (!force && now.difference(_lastCameraUpdate) < _cameraUpdateInterval) {
      return;
    }
    _lastCameraUpdate = now;

    final speed = position.speedKmh.clamp(0.0, 160.0).toDouble();
    final zoom = _navigationZoom(speed);
    final bearing = _smoothNavigationBearing(
      position.headingDeg,
      speedKmh: speed,
      now: now,
    );
    final camera = ml.CameraPosition(
      target: _navigationCameraTarget(position, zoom),
      zoom: widget.drivingMode ? zoom : math.max(zoom - 1.2, 14.5),
      bearing: bearing,
      tilt: widget.drivingMode
          ? widget.cameraTiltDegrees.clamp(42.0, 55.0).toDouble()
          : widget.cameraTiltDegrees.clamp(0.0, 60.0).toDouble(),
    );

    // Coalesce native camera commands. Never let several moveCamera calls
    // execute out of order; the newest GPS frame always wins.
    _pendingCameraPosition = camera;
    if (_cameraMoveRunning) return;
    _cameraMoveRunning = true;
    unawaited(_drainCameraMoves(controller));
  }

  Future<void> _drainCameraMoves(ml.MapLibreMapController controller) async {
    try {
      while (mounted && controller == _controller && widget.followVehicle) {
        final camera = _pendingCameraPosition;
        _pendingCameraPosition = null;
        if (camera == null) break;
        try {
          // moveCamera is a hard cut with no interpolation; at a 50ms tick
          // cadence that produced a visible stutter/jump on every frame
          // instead of a smooth pan+rotate, most noticeable on turns and
          // right after a reroute snaps the marker onto a new road. The
          // vehicle position feeding this call is already a continuously
          // smoothed 60fps stream (see VehiclePositionAnimator), so the
          // camera only needs to glide from its current pose to the next
          // sample over the same interval, not snap to it.
          await controller.animateCamera(
            ml.CameraUpdate.newCameraPosition(camera),
            duration: _cameraUpdateInterval,
          );
        } catch (_) {
          break;
        }
      }
    } finally {
      _cameraMoveRunning = false;
      // A GPS frame may have arrived between the final read and releasing the
      // lock. Consume it once, rather than starting another native queue.
      if (_pendingCameraPosition != null &&
          mounted &&
          controller == _controller &&
          widget.followVehicle) {
        _cameraMoveRunning = true;
        unawaited(_drainCameraMoves(controller));
      }
    }
  }

  double _smoothNavigationBearing(
    double target,
    {required double speedKmh, required DateTime now}) {
    if (!target.isFinite) {
      return _smoothedCameraBearing ?? 0.0;
    }
    final normalized = (target % 360.0 + 360.0) % 360.0;
    final previous = _smoothedCameraBearing;
    if (previous == null || _lastCameraBearingAt == null) {
      _smoothedCameraBearing = normalized;
      _lastCameraBearingAt = now;
      return normalized;
    }

    final dt = now.difference(_lastCameraBearingAt!).inMicroseconds / 1e6;
    _lastCameraBearingAt = now;
    final safeDt = dt.clamp(0.016, 0.12);

    // At very low speed GNSS heading is often noise. Hold the last stable
    // camera direction instead of allowing a stopped vehicle to spin the map.
    if (speedKmh < 3.0) return previous;

    var delta = ((normalized - previous + 540.0) % 360.0) - 180.0;
    if (delta.abs() < 1.5) return previous;

    // Limit camera angular velocity. The marker/vehicle heading is already
    // smoothed by VehiclePositionAnimator; the camera must not rotate faster
    // than that visual motion on a single GPS sample, especially through
    // 90-degree turns and roundabouts.
    final maxStep = (150.0 * safeDt).clamp(1.0, 18.0);
    delta = delta.clamp(-maxStep, maxStep).toDouble();
    final next = (previous + delta) % 360.0;
    _smoothedCameraBearing = next < 0 ? next + 360.0 : next;
    return _smoothedCameraBearing!;
  }

  double _navigationZoom(double speedKmh) {
    // بازه با درنظر گرفتن maxZoom=18: در سرعت پایین تا 17.5 (نمای خیابانی)
    // و در سرعت بالا به 15.4 نرم می‌رسد. کاربر همچنان می‌تواند با gesture
    // تا 18 zoom کند.
    if (speedKmh < 15) return 17.5;
    if (speedKmh < 40) return 17.0;
    if (speedKmh < 70) return 16.4;
    if (speedKmh < 100) return 15.8;
    return 15.4;
  }

  void _onCameraMove(ml.CameraPosition camera) {
    _camera = camera;
    widget.onCameraPositionChanged?.call(camera);
    unawaited(_refreshScreenPositions());
    _scheduleAbmRefresh();
  }

  Future<void> _refreshScreenPositions() async {
    final requestGeneration = ++_screenUpdateGeneration;

    // The vehicle marker must remain geographically attached to the same
    // coordinate that the route renderer draws. A fixed screen coordinate
    // (previously 50% x / 66% y) was only an approximation: camera bearing,
    // tilt and the route-ahead target mean that the fixed point is not
    // necessarily the vehicle's road coordinate. On bends this made the car
    // visibly leave the turquoise route even though its LatLng was correct.
    // Always project the actual animated vehicle coordinate through MapLibre;
    // the camera may move, but the marker stays on the road.

    if (_screenUpdateRunning) {
      _screenUpdateQueued = true;
      return;
    }
    final controller = _controller;
    if (controller == null) return;
    _screenUpdateRunning = true;
    try {
      final position = widget.vehiclePosition;
      final vehiclePoint = position == null
          ? null
          : await controller
              .toScreenLocation(_toMapLibreVehiclePoint(position));
      final destination = widget.destination;
      final destinationPoint = destination == null
          ? null
          : await controller.toScreenLocation(_toMapLibrePoint(destination));

      // A projection belongs to the camera frame that requested it. Discard
      // it if a newer camera/GPS frame has already been requested.
      if (requestGeneration != _screenUpdateGeneration ||
          !mounted ||
          controller != _controller) {
        return;
      }

      final pixelRatio = MediaQuery.devicePixelRatioOf(context);
      setState(() {
        _vehicleScreen = vehiclePoint == null
            ? null
            : mapScreenPointToFlutterOffset(vehiclePoint, pixelRatio);
        _destinationScreen = destinationPoint == null
            ? null
            : mapScreenPointToFlutterOffset(destinationPoint, pixelRatio);
      });
    } catch (_) {
      // During style replacement projection may temporarily be unavailable.
    } finally {
      _screenUpdateRunning = false;
      if (_screenUpdateQueued) {
        _screenUpdateQueued = false;
        unawaited(_refreshScreenPositions());
      }
    }
  }

  Future<void> _onMapClick(math.Point<double> screenPoint, ml.LatLng point) async {
    final tap = LatLng(point.latitude, point.longitude);
    final routeIndex = _hitTestRoute(tap, _routeOverlays);
    if (routeIndex != null) {
      widget.onRouteTap?.call(routeIndex);
      return;
    }
    if (widget.localStylePath != null && _controller != null) {
      try {
        final featureLayers = widget.localStylePath != null
            ? const ['poi-points', 'poi-labels', 'abm-road-local-labels', 'abm-road-line', 'label_city']
            : const ['poi-points', 'poi-labels', 'highway-name-major', 'highway-name-minor', 'label_city', 'road_minor'];
        final features = await _controller!.queryRenderedFeatures(
          screenPoint,
          featureLayers,
          null,
        );
        if (features.isNotEmpty) {
          final first = features.first;
          final props = first is Map && first['properties'] is Map
              ? Map<String, dynamic>.from(first['properties'] as Map)
              : <String, dynamic>{};
          if (props.isNotEmpty) {
            widget.onMapTap?.call(tap, props);
            widget.onPoiTap?.call(props);
            return;
          }
        }
      } catch (error) {
        
      }
    }
    widget.onMapTap?.call(tap, const <String, dynamic>{});
  }

  void _onMapLongClick(math.Point<double> _, ml.LatLng point) {
    widget.onLongPress?.call(LatLng(point.latitude, point.longitude));
  }

  int? _hitTestRoute(LatLng tap, List<OnlineRouteOverlay> overlays) {
    const hitRadiusMeters = 30.0;
    var bestDistance = hitRadiusMeters;
    int? bestIndex;
    for (var routeIndex = 0; routeIndex < overlays.length; routeIndex++) {
      final geometry = overlays[routeIndex].geometry;
      for (var pointIndex = 1; pointIndex < geometry.length; pointIndex++) {
        final distance = _distanceToSegmentMeters(
          tap,
          geometry[pointIndex - 1],
          geometry[pointIndex],
        );
        if (distance <= bestDistance) {
          bestDistance = distance;
          bestIndex = routeIndex;
        }
      }
    }
    return bestIndex;
  }

  double _distanceToSegmentMeters(LatLng point, LatLng start, LatLng end) {
    final latitudeRadians = point.latitude * math.pi / 180.0;
    final metersPerLongitude = 111320.0 * math.cos(latitudeRadians);
    final abX = (end.longitude - start.longitude) * metersPerLongitude;
    final abY = (end.latitude - start.latitude) * 110540.0;
    final apX = (point.longitude - start.longitude) * metersPerLongitude;
    final apY = (point.latitude - start.latitude) * 110540.0;
    final lengthSquared = abX * abX + abY * abY;
    if (lengthSquared <= 1e-6) return math.sqrt(apX * apX + apY * apY);
    final projection =
        ((apX * abX + apY * abY) / lengthSquared).clamp(0.0, 1.0);
    final nearestX = abX * projection;
    final nearestY = abY * projection;
    final dx = apX - nearestX;
    final dy = apY - nearestY;
    return math.sqrt(dx * dx + dy * dy);
  }

  double get _markerVisualSize {
    // Keep the map anchor box independent from the car-size preference.
    // The 3D model itself is scaled inside this fixed box.
    if (widget.showCarModel) return 72.0;
    return (40.0 * (widget.pinSizePercent / 100)).clamp(30.0, 82.0).toDouble();
  }

  double _effectiveVehicleHeading(VehiclePosition position) {
    final route = widget.routeGeometry;
    // در سرعت کم، GPS معمولاً heading صفر/نویزدار می‌دهد. در حالت ناوبری
    // جهت نزدیک‌ترین قطعهٔ مسیر پایدارتر است و خودرو روی خط عمودی نمی‌ماند.
    if (route == null || route.length < 2 || position.speedKmh >= 3) {
      return position.headingDeg;
    }
    var bestDistance = double.infinity;
    var bestHeading = position.headingDeg;
    final point = LatLng(position.lat, position.lng);
    for (var i = 0; i < route.length - 1; i++) {
      final distance = _distanceToSegmentMeters(point, route[i], route[i + 1]);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestHeading = _bearingBetween(route[i], route[i + 1]);
      }
    }
    return bestHeading;
  }

  double _bearingBetween(LatLng a, LatLng b) {
    final y = (b.longitude - a.longitude) *
        math.cos((a.latitude + b.latitude) * math.pi / 360.0);
    final x = b.latitude - a.latitude;
    return (math.atan2(y, x) * 180.0 / math.pi + 360.0) % 360.0;
  }

  @override
  Widget build(BuildContext context) {
    final vehiclePosition = _vehicleScreen;
    final destinationPosition = _destinationScreen;
    final markerSize = _markerVisualSize;
    final mapBearing = _camera?.bearing ?? 0;
    // tilt واقعیِ MapLibre مرجع اصلی مدل است؛ نه فقط مقدار تنظیمات اولیه.
    // به این ترتیب اگر کاربر نقشه را با gesture از 2D به هر زاویه‌ای ببرد،
    // نمای خودرو در همان فریم به پرسپکتیؤ نقشه نزدیک می‌شود.
    final actualMapTilt =
        (_camera?.tilt ?? widget.cameraTiltDegrees).clamp(0.0, 60.0).toDouble();
    final effectiveCarCameraAngle = math
        .max(
          widget.carCameraAngleDegrees.clamp(0.0, 90.0),
          (actualMapTilt * 1.5).clamp(0.0, 90.0),
        )
        .toDouble();
    // asset پیکان در حالت پایه رو به بالای صفحه (شمال) است؛ بنابراین تنها
    // چرخش لازم، اختلاف heading جغرافیایی با bearing فعلی نقشه است. offset
    // قبلیِ -90 باعث می‌شد مکان‌نما یک ربع‌گردش از مسیر واقعی منحرف باشد.
    final geographicHeading = widget.vehiclePosition == null
        ? 0.0
        : _effectiveVehicleHeading(widget.vehiclePosition!);
    final screenHeading = mapRelativeHeading(geographicHeading, mapBearing);

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => widget.onUserGestureStart?.call(),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ml.MapLibreMap(
            styleString: widget.localStylePath ??
                (throw StateError('Unified local MapLibre style was not resolved')),
            initialCameraPosition: _computeInitialCameraPosition(),
            minMaxZoomPreference:
                ml.MinMaxZoomPreference(_minMapZoom, _maxMapZoom),
            compassEnabled: false,
            myLocationEnabled: false,
            myLocationTrackingMode: ml.MyLocationTrackingMode.none,
            logoEnabled: false,
            scaleControlEnabled: false,
            rotateGesturesEnabled: true,
            scrollGesturesEnabled: true,
            zoomGesturesEnabled: true,
            tiltGesturesEnabled: true,
            trackCameraPosition: true,
            // Do not eagerly initialize MapLibre's AnnotationManager while
            // the Android activity/view is still attaching. Older maplibre_gl
            // builds call addLineLayer from the controller constructor and can
            // throw MAP_NOT_READY during activity recreation. Route lines are
            // added lazily after onStyleLoaded instead.
            foregroundLoadColor: widget.palette.background,
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoaded,
            onMapClick: _onMapClick,
            onMapLongClick: _onMapLongClick,
            onCameraMove: _onCameraMove,
            onCameraIdle: () {
              unawaited(_refreshScreenPositions());
              // In follow mode the camera re-centers on every GPS tick, so
              // this idle event fires right after the position-change
              // handler already decided (via `_needsAbmReload`) whether a
              // reload was warranted. Re-checking here instead of always
              // reloading avoids a second, redundant viewport query for the
              // same GPS fix. A manual pan/zoom (not following) always
              // reloads, since it can reveal an area GPS-based gating knows
              // nothing about.
              final gps = widget.vehiclePosition;
              final skipRedundantReload = widget.followVehicle &&
                  gps != null &&
                  !_needsAbmReload(gps.lat, gps.lng);
              if (!skipRedundantReload) {
                _scheduleAbmRefresh();
              }
              widget.onCameraIdle?.call();
            },
          ),
          if (destinationPosition != null)
            Positioned(
              left: destinationPosition.dx - 21,
              top: destinationPosition.dy - 42,
              child: const IgnorePointer(
                child: Icon(
                  Icons.location_on_rounded,
                  color: Color(0xFFE84A5F),
                  size: 42,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 5)],
                ),
              ),
            ),
          // Keep the ModelViewer mounted even while GPS/map projection is
          // temporarily unavailable. model_viewer_plus initializes its
          // controller asynchronously; removing it during that gap can
          // trigger setState-after-dispose inside the plugin.
          if (widget.showCarModel)
            Positioned(
              left: (vehiclePosition?.dx ?? -markerSize) - markerSize / 2,
              top: (vehiclePosition?.dy ?? -markerSize) - markerSize * 0.50,
              width: markerSize,
              height: markerSize,
              child: IgnorePointer(
                child: vehiclePosition == null
                    ? const SizedBox.shrink()
                    : Transform(
                        alignment: Alignment.bottomCenter,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.0007)
                          ..rotateX(-actualMapTilt * math.pi / 180.0 * 0.22),
                        child: CarMarker3D(
                          size: markerSize,
                          modelIndex: widget.modelIndex,
                          headingDeg: screenHeading,
                          cameraAngleDegrees: effectiveCarCameraAngle,
                          sizePercent: widget.carSizePercent,
                          interactive: false,
                        ),
                      ),
              ),
            ),
          if (!widget.showCarModel && vehiclePosition != null)
            Positioned(
              left: vehiclePosition.dx - markerSize / 2,
              top: vehiclePosition.dy - markerSize * 0.50,
              width: markerSize,
              height: markerSize,
              child: IgnorePointer(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.rotate(
                      angle: screenHeading * math.pi / 180,
                      child: NavArrow(
                        size: markerSize,
                        color: widget.markerColor,
                        glow: widget.pinShadowEnabled,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
