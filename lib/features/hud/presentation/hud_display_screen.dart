import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/geo/geo_types.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../gps/data/location_service.dart';
import '../../gps/presentation/gps_providers.dart';
import '../../routing/data/routing_service.dart'
    show RouteAlert, RouteAlertType, RouteInstruction;
import '../../routing/presentation/routing_providers.dart';
import '../domain/hud_maneuver_icon.dart';
import 'hud_settings_providers.dart';

/// نزدیک‌ترین [RouteAlert] جلوی خودرو، در بازهٔ [maxDistanceM] و در مخروطِ
/// جلوی heading — همان الگویی که home_screen.dart برای نشان‌دادن هشدار
/// جاده روی نقشهٔ اصلی استفاده می‌کند، اینجا برای بلاکِ HUD تکرار شده تا
/// آیکونِ ثابتِ قبلی (که به هیچ داده‌ای وصل نبود) با یک هشدارِ واقعی
/// جایگزین شود.
RouteAlert? nearestAheadRouteAlert(
  ActiveNavigation? nav,
  VehiclePosition? position, {
  double maxDistanceM = 300.0,
  double maxBearingDeltaDeg = 70.0,
}) {
  if (nav == null || position == null) return null;
  RouteAlert? best;
  var bestDistance = double.infinity;
  for (final alert in nav.route.alerts) {
    final distance = _hudDistanceM(
      position.lat,
      position.lng,
      alert.location.latitude,
      alert.location.longitude,
    );
    if (distance > maxDistanceM || distance >= bestDistance) continue;
    if (position.headingDeg.isFinite) {
      final bearing = _hudBearingDeg(
        position.lat,
        position.lng,
        alert.location.latitude,
        alert.location.longitude,
      );
      final delta = ((bearing - position.headingDeg + 540) % 360) - 180;
      if (delta.abs() > maxBearingDeltaDeg) continue;
    }
    best = alert;
    bestDistance = distance;
  }
  return best;
}

IconData hudAlertIcon(RouteAlertType type) {
  switch (type) {
    case RouteAlertType.speedCamera:
      return Icons.camera_alt_rounded;
    case RouteAlertType.speedBump:
      return Icons.warning_amber_rounded;
    case RouteAlertType.policeCheckpoint:
      return Icons.local_police_rounded;
    case RouteAlertType.trafficLight:
      return Icons.traffic_rounded;
  }
}

double _hudDistanceM(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * math.pi / 180.0;
  final dLng = (lng2 - lng1) * math.pi / 180.0;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180.0) *
          math.cos(lat2 * math.pi / 180.0) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _hudBearingDeg(double lat1, double lng1, double lat2, double lng2) {
  final p1 = lat1 * math.pi / 180.0;
  final p2 = lat2 * math.pi / 180.0;
  final dl = (lng2 - lng1) * math.pi / 180.0;
  final y = math.sin(dl) * math.cos(p2);
  final x =
      math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl);
  return (math.atan2(y, x) * 180.0 / math.pi + 360.0) % 360.0;
}

/// نمایشِ واقعیِ HUD حین رانندگی.
///
/// قبلاً این صفحه فلشِ «مستقیم» را ثابت نشان می‌داد (رجوع کنید به تصویرِ
/// باگ). حالا آیکونِ جهت از [hudManeuverIcon] و از رویِ دستورِ واقعیِ
/// ناوبریِ جاری (`activeNavigationProvider`) ساخته می‌شود؛ یعنی برای هر
/// میدان یا پیچ به هر سمت، همان جهتِ واقعی (چپ/راست/تند/ملایم/میدان/دور زدن)
/// نمایش داده می‌شود، نه یک فلشِ یکسان برای همه‌ی حالت‌ها.
class HudDisplayScreen extends ConsumerStatefulWidget {
  const HudDisplayScreen({super.key});

  @override
  ConsumerState<HudDisplayScreen> createState() => _HudDisplayScreenState();
}

class _HudDisplayScreenState extends ConsumerState<HudDisplayScreen> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _validateHudConditions(HudSettings settings, ActiveNavigation? nav) {
    final landscape = MediaQuery.of(context).orientation ==
            Orientation.landscape &&
        MediaQuery.of(context).size.width > MediaQuery.of(context).size.height;
    if (settings.enabled && nav != null && landscape) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.canPop()) context.pop();
    });
  }

  String _compassLabel(double? headingDeg) {
    if (headingDeg == null) return '--';
    const labels = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final idx = (((headingDeg % 360) + 22.5) / 45).floor() % 8;
    return labels[idx];
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(hudSettingsProvider);
    final nav = ref.watch(activeNavigationProvider);
    final vehiclePositionAsync = ref.watch(vehiclePositionProvider);
    final accent = AppColors.primaryAccent(context);
    _validateHudConditions(settings, nav);
    String t(String key) => AppStrings.get(context, ref, key);

    final vehiclePosition = vehiclePositionAsync.value;
    final speedKmh = vehiclePosition?.speedKmh ?? 0;
    final headingDeg = vehiclePosition?.headingDeg;
    final instruction = nav?.currentInstruction;
    final aheadAlert = nearestAheadRouteAlert(nav, vehiclePosition);

    final scale = (settings.scalePercent / 100).clamp(0.5, 1.3);
    final brightness = (settings.brightnessPercent / 100).clamp(0.10, 1.0);

    Widget content = Container(
      color: Colors.black,
      child: SafeArea(
        child: Opacity(
          opacity: brightness,
          child: Align(
            alignment: Alignment(
              settings.horizontalOffset,
              settings.verticalOffset,
            ),
            child: Transform.scale(
              scale: scale,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (settings.showSpeed) _SpeedBlock(speedKmh: speedKmh),
                        if (settings.showSpeedLimit &&
                            instruction?.speedLimit != null &&
                            speedKmh >= instruction!.speedLimit! - 10) ...[
                          const SizedBox(width: 18),
                          _SpeedLimitCircle(limit: instruction.speedLimit!),
                        ],
                        const Spacer(),
                        if (settings.showCompassHeading)
                          _CompassBlock(label: _compassLabel(headingDeg)),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (nav != null &&
                        (settings.showNextManeuver ||
                            settings.showDistanceToManeuver))
                      _ManeuverBlock(
                        accent: accent,
                        instruction: instruction,
                        distanceM: nav.distanceToNextManeuverM,
                        showIcon: settings.showNextManeuver,
                        showDistance: settings.showDistanceToManeuver,
                        arrivedLabel: t('hud_arrived'),
                      )
                    else if (settings.showNextManeuver)
                      Text(
                        t('hud_no_active_navigation'),
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 14),
                      ),
                    if (settings.showAiAlerts && aheadAlert != null) ...[
                      const SizedBox(height: 10),
                      Icon(hudAlertIcon(aheadAlert.type),
                          color: Colors.amber, size: 26),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      'ABTINMAP HUD',
                      style: TextStyle(
                        color: accent.withOpacity(0.8),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (settings.mirrorImage) {
      content = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()..scale(-1.0, 1.0, 1.0),
        child: content,
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: content),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white54),
              onPressed: () => context.pop(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeedBlock extends StatelessWidget {
  const _SpeedBlock({required this.speedKmh});
  final double speedKmh;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            speedKmh.round().toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 56,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const Text('km/h',
              style: TextStyle(color: Colors.white54, fontSize: 13)),
        ],
      );
}

class _SpeedLimitCircle extends StatelessWidget {
  const _SpeedLimitCircle({required this.limit});
  final int limit;

  @override
  Widget build(BuildContext context) => Container(
        width: 54,
        height: 54,
        margin: const EdgeInsets.only(top: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: Colors.red, width: 5),
        ),
        child: Text(
          '$limit',
          style: const TextStyle(
              color: Colors.black, fontWeight: FontWeight.w900, fontSize: 20),
        ),
      );
}

class _CompassBlock extends StatelessWidget {
  const _CompassBlock({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          const Icon(Icons.explore_rounded,
              color: Colors.lightBlueAccent, size: 22),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: Colors.lightBlueAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ],
      );
}

/// بلاکِ مرکزیِ HUD: آیکونِ جهتِ واقعیِ پیچ/میدان بعدی (نه یک فلشِ ثابت)
/// به‌همراهِ فاصله تا آن.
class _ManeuverBlock extends StatelessWidget {
  const _ManeuverBlock({
    required this.accent,
    required this.instruction,
    required this.distanceM,
    required this.showIcon,
    required this.showDistance,
    required this.arrivedLabel,
  });

  final Color accent;
  final RouteInstruction? instruction;
  final double distanceM;
  final bool showIcon;
  final bool showDistance;
  final String arrivedLabel;

  @override
  Widget build(BuildContext context) {
    final instr = instruction;
    if (instr == null) return const SizedBox.shrink();
    final String type = instr.type;
    final String? modifier = instr.modifier;
    final bool arrived = type == 'arrive';

    return Column(
      children: [
        if (showIcon)
          Transform.rotate(
            angle:
                arrived ? 0 : hudManeuverRotationRadiansIfPlain(type, modifier),
            child: Icon(
              hudManeuverIcon(type, modifier),
              color: accent,
              size: 72,
            ),
          ),
        const SizedBox(height: 6),
        if (arrived)
          Text(
            arrivedLabel,
            style: TextStyle(
                color: accent, fontSize: 16, fontWeight: FontWeight.w800),
          )
        else if (showDistance)
          Text(
            distanceM >= 1000
                ? '${(distanceM / 1000).toStringAsFixed(1)} km'
                : '${distanceM.round()} m',
            style: TextStyle(
                color: accent, fontSize: 18, fontWeight: FontWeight.w800),
          ),
      ],
    );
  }
}

/// [hudManeuverIcon] برای اکثرِ حالت‌ها آیکونِ اختصاصیِ صحیح برمی‌گرداند
/// (که خودش چرخیده است)، پس نیازی به چرخشِ اضافه نیست. این تابع فقط صفر
/// برمی‌گرداند تا در آینده اگر خواستیم برای آیکونِ ساده‌ی فلش هم چرخش
/// دستی اضافه کنیم، به‌جای دستکاریِ ویجت بالا همین‌جا تغییر بدهیم.
double hudManeuverRotationRadiansIfPlain(String type, String? modifier) => 0;
