import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:abtin_maps/core/geo/geo_types.dart';
import '../../../core/localization/app_localizations.dart';

import '../../../shared/providers/abtinmap_providers.dart';
import '../../../shared/providers/app_settings_providers.dart';
import 'abtinmap_routing_provider.dart';
import 'online_routing_provider.dart';
import 'routing_provider.dart';

class RouteInfo {
  const RouteInfo({
    required this.geometry,
    required this.distanceKm,
    required this.durationMin,
    required this.instructions,
    this.alerts = const [],
  });

  final List<LatLng> geometry;
  final double distanceKm;
  final double durationMin;
  final List<RouteInstruction> instructions;
  final List<RouteAlert> alerts;
}

enum RouteAlertType { speedCamera, speedBump, policeCheckpoint, trafficLight }

class RouteAlert {
  const RouteAlert({required this.type, required this.location, this.name});
  final RouteAlertType type;
  final LatLng location;
  final String? name;
}

class RouteInstruction {
  const RouteInstruction({
    required this.text,
    required this.distanceMeters,
    required this.location,
    required this.type,
    this.modifier,
    this.exit,
    this.roundaboutAngleDegrees,
    this.roundaboutExitCount,
    this.roundaboutBranchAngles = const [],
    this.roundaboutEntranceAngles = const [],
    this.roundaboutExitAngles = const [],
    this.roundaboutActiveExitAngle,
    this.drivingSide = 'right',
    this.speedLimit,
    this.maneuverEndLocation,
  });

  final String text;
  final double distanceMeters;
  final LatLng location;
  final String type;
  final String? modifier;
  final int? exit;
  final double? roundaboutAngleDegrees;

  /// Total number of usable exits detected for this roundabout.
  final int? roundaboutExitCount;

  /// Actual physical arm bearings discovered from the offline SQLite graph.
  /// These replace the old hard-coded four-branch drawing.
  final List<double> roundaboutBranchAngles;
  final List<double> roundaboutEntranceAngles;
  final List<double> roundaboutExitAngles;
  final double? roundaboutActiveExitAngle;

  /// 'left' or 'right' - which side of the road the source country drives
  /// on. Roundabouts are traversed clockwise under right-hand traffic and
  /// counter-clockwise under left-hand traffic; the guidance icon uses this
  /// to draw the correct rotation instead of assuming one country.
  final String drivingSide;
  final int? speedLimit;

  /// For a roundabout this is the point where the vehicle actually leaves
  /// the roundabout. It prevents the next instruction from replacing the
  /// roundabout guidance while the driver is still inside it.
  final LatLng? maneuverEndLocation;
}

/// تنها درگاه مسیریابی اپ: graph داخل فایل ABM نصب‌شده روی دستگاه.
/// این کلاس هیچ endpoint، client HTTP یا fallback شبکه‌ای ندارد.
class RoutingService {
  RoutingService(this._ref);

  final Ref _ref;
  AbtinmapRoutingProvider? _abmProvider;
  OnlineRoutingProvider? _onlineProvider;
  String? lastError;

  /// موتور فعال از provider سراسری خوانده می‌شود تا با انتخاب کاربر در
  /// تنظیمات، محاسبهٔ مسیر بعدی واقعاً به همان منبع هدایت شود.
  RoutingEngine get engine => _ref.read(routingEngineProvider);

  AbtinmapRoutingProvider get abtinmapProvider {
    // The active ABM can change from the Downloads screen. The old singleton
    // kept the constructor default `IR.abm`, so routing could keep opening an
    // old graph even after another country/region was selected.
    final activeMap = _ref.read(abmActiveMapNameProvider).trim();
    if (_abmProvider == null || _abmProvider!.mapName != activeMap) {
      _abmProvider = AbtinmapRoutingProvider(
        mapService: _ref.read(abmMapServiceProvider),
        vectorMapService: _ref.read(vectorMapServiceProvider),
        mapName: activeMap.isEmpty ? 'IR.abm' : activeMap,
        languageCode: () => _ref.read(languageProvider),
      );
    }
    return _abmProvider!;
  }

  OnlineRoutingProvider get onlineProvider =>
      _onlineProvider ??= OnlineRoutingProvider(
        languageCode: () => _ref.read(languageProvider),
      );

  Future<RouteInfo?> calculateRoute({
    required LatLng origin,
    required LatLng destination,
    bool offlineOnly = false,
    bool avoidUnpavedRoads = false,
    bool avoidTolls = false,
  }) async {
    lastError = null;
    if (!offlineOnly && engine == RoutingEngine.online) {
      final route = await onlineProvider.calculateRoute(
        origin: origin,
        destination: destination,
      );
      if (route != null) return route;
      lastError = onlineProvider.lastError ??
          AppStrings.getForLanguage(
              _ref.read(languageProvider), 'route_error_online_failed_generic');
      return null;
    }

    final route = await abtinmapProvider.calculateRoute(
      origin: origin,
      destination: destination,
      offlineOnly: true,
      avoidUnpavedRoads: avoidUnpavedRoads,
      avoidTolls: avoidTolls,
    );
    if (route != null) return route;
    lastError = abtinmapProvider.lastError ??
        AppStrings.getForLanguage(
            _ref.read(languageProvider), 'route_error_offline_map_missing');
    return null;
  }

  Future<List<RouteInfo>> calculateRoutes({
    required LatLng origin,
    required LatLng destination,
    bool offlineOnly = false,
    bool avoidUnpavedRoads = false,
    bool avoidTolls = false,
  }) async {
    lastError = null;
    if (!offlineOnly && engine == RoutingEngine.online) {
      final routes = await onlineProvider.calculateRoutes(
        origin: origin,
        destination: destination,
      );
      if (routes.isEmpty) {
        lastError = onlineProvider.lastError ??
            AppStrings.getForLanguage(_ref.read(languageProvider),
                'route_error_online_failed_generic');
      }
      return routes;
    }

    final routes = await abtinmapProvider.calculateRoutes(
      origin: origin,
      destination: destination,
      offlineOnly: true,
      avoidUnpavedRoads: avoidUnpavedRoads,
      avoidTolls: avoidTolls,
    );
    if (routes.isEmpty) {
      lastError = abtinmapProvider.lastError ??
          'برای مسیریابی، ابتدا یک نقشهٔ آفلاین ABM نصب کنید.';
    }
    return routes;
  }

  void dispose() {
    _onlineProvider?.dispose();
  }
}
