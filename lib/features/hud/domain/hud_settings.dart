import 'dart:convert';
import 'package:flutter/foundation.dart';

/// مدلِ واحد و غیرقابل‌تغییرِ تنظیماتِ «هد آپ دیسپلی» (HUD).
///
/// همانند DashCamSettings/AppearanceSettings، همه‌ی مقادیر در یک شیء واحد
/// نگه‌داری و با یک کلید JSON در SettingsRepository ذخیره می‌شوند.
@immutable
class HudSettings {
  const HudSettings({
    this.enabled = false,
    this.brightnessPercent = 70,
    this.mirrorImage = true,
    this.scalePercent = 100,
    this.showSpeed = true,
    this.showSpeedLimit = true,
    this.showNextManeuver = true,
    this.showDistanceToManeuver = true,
    this.showCompassHeading = true,
    this.showRouteAlerts = true,
    this.showAiAlerts = true,
    this.showOtherInfo = false,
    this.horizontalOffset = 0.0,
    this.verticalOffset = 0.0,
  });

  final bool enabled;

  /// ۱۰ تا ۱۰۰ درصد.
  final int brightnessPercent;

  /// آینه‌ای کردن تصویر برای بازتاب صحیح روی شیشه جلو.
  final bool mirrorImage;

  /// ۵۰ تا ۱۳۰ درصد.
  final int scalePercent;

  final bool showSpeed;
  final bool showSpeedLimit;
  final bool showNextManeuver;
  final bool showDistanceToManeuver;
  final bool showCompassHeading;
  final bool showRouteAlerts;
  final bool showAiAlerts;
  final bool showOtherInfo;

  /// جابه‌جایی موقعیت کلی نمایش روی شیشه (-1.0 تا 1.0، نسبت به مرکز).
  final double horizontalOffset;
  final double verticalOffset;

  HudSettings copyWith({
    bool? enabled,
    int? brightnessPercent,
    bool? mirrorImage,
    int? scalePercent,
    bool? showSpeed,
    bool? showSpeedLimit,
    bool? showNextManeuver,
    bool? showDistanceToManeuver,
    bool? showCompassHeading,
    bool? showRouteAlerts,
    bool? showAiAlerts,
    bool? showOtherInfo,
    double? horizontalOffset,
    double? verticalOffset,
  }) {
    return HudSettings(
      enabled: enabled ?? this.enabled,
      brightnessPercent: brightnessPercent ?? this.brightnessPercent,
      mirrorImage: mirrorImage ?? this.mirrorImage,
      scalePercent: scalePercent ?? this.scalePercent,
      showSpeed: showSpeed ?? this.showSpeed,
      showSpeedLimit: showSpeedLimit ?? this.showSpeedLimit,
      showNextManeuver: showNextManeuver ?? this.showNextManeuver,
      showDistanceToManeuver:
          showDistanceToManeuver ?? this.showDistanceToManeuver,
      showCompassHeading: showCompassHeading ?? this.showCompassHeading,
      showRouteAlerts: showRouteAlerts ?? this.showRouteAlerts,
      showAiAlerts: showAiAlerts ?? this.showAiAlerts,
      showOtherInfo: showOtherInfo ?? this.showOtherInfo,
      horizontalOffset: horizontalOffset ?? this.horizontalOffset,
      verticalOffset: verticalOffset ?? this.verticalOffset,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'brightnessPercent': brightnessPercent,
        'mirrorImage': mirrorImage,
        'scalePercent': scalePercent,
        'showSpeed': showSpeed,
        'showSpeedLimit': showSpeedLimit,
        'showNextManeuver': showNextManeuver,
        'showDistanceToManeuver': showDistanceToManeuver,
        'showCompassHeading': showCompassHeading,
        'showRouteAlerts': showRouteAlerts,
        'showAiAlerts': showAiAlerts,
        'showOtherInfo': showOtherInfo,
        'horizontalOffset': horizontalOffset,
        'verticalOffset': verticalOffset,
      };

  String serialize() => jsonEncode(toJson());

  static bool _boolOr(dynamic raw, bool fallback) =>
      raw is bool ? raw : fallback;

  static int _intOr(dynamic raw, int fallback) =>
      raw is num ? raw.toInt() : fallback;

  static double _numOr(dynamic raw, double fallback) =>
      raw is num ? raw.toDouble() : fallback;

  factory HudSettings.deserialize(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      const fallback = HudSettings();
      return HudSettings(
        enabled: _boolOr(map['enabled'], fallback.enabled),
        brightnessPercent:
            _intOr(map['brightnessPercent'], fallback.brightnessPercent),
        mirrorImage: _boolOr(map['mirrorImage'], fallback.mirrorImage),
        scalePercent: _intOr(map['scalePercent'], fallback.scalePercent),
        showSpeed: _boolOr(map['showSpeed'], fallback.showSpeed),
        showSpeedLimit: _boolOr(map['showSpeedLimit'], fallback.showSpeedLimit),
        showNextManeuver:
            _boolOr(map['showNextManeuver'], fallback.showNextManeuver),
        showDistanceToManeuver: _boolOr(
            map['showDistanceToManeuver'], fallback.showDistanceToManeuver),
        showCompassHeading:
            _boolOr(map['showCompassHeading'], fallback.showCompassHeading),
        showRouteAlerts:
            _boolOr(map['showRouteAlerts'], fallback.showRouteAlerts),
        showAiAlerts: _boolOr(map['showAiAlerts'], fallback.showAiAlerts),
        showOtherInfo: _boolOr(map['showOtherInfo'], fallback.showOtherInfo),
        horizontalOffset:
            _numOr(map['horizontalOffset'], fallback.horizontalOffset),
        verticalOffset: _numOr(map['verticalOffset'], fallback.verticalOffset),
      );
    } catch (_) {
      return const HudSettings();
    }
  }
}
