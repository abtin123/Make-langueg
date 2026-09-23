import 'dart:convert';
import 'package:flutter/foundation.dart';

/// سطح حساسیتِ هر هشدارِ دستیارِ راننده.
enum DashCamAlertLevel { off, low, normal, high }

/// مدلِ واحد و غیرقابل‌تغییرِ تنظیماتِ «دوربین هوشمند خودرو» (AI DashCam).
///
/// همانند [AppearanceSettings]، همه‌ی مقادیر در یک شیء واحد نگه‌داری و با
/// یک کلید JSON در SettingsRepository ذخیره می‌شوند.
@immutable
class DashCamSettings {
  const DashCamSettings({
    this.recordingEnabled = false,
    this.videoSizeMinutes = 30,
    this.driverAssistanceEnabled = false,
    this.fixedCameraHeight = false,
    this.cameraHeightMeters = 1.20,
    this.vehicleWidthMeters = 1.80,
    this.cameraLateralDisplacementMeters = 0.0,
    this.forwardCollision = DashCamAlertLevel.normal,
    this.dangerousHeadway = DashCamAlertLevel.normal,
    this.stopAndGo = DashCamAlertLevel.normal,
    this.laneDepartureSolid = DashCamAlertLevel.normal,
    this.laneDepartureDashed = DashCamAlertLevel.normal,
    this.trafficSignRecognition = DashCamAlertLevel.normal,
  });

  final bool recordingEnabled;

  /// طول هر بخشِ ضبط‌شده به دقیقه؛ ۰ به‌معنیِ نامحدود (∞).
  final int videoSizeMinutes;

  final bool driverAssistanceEnabled;
  final bool fixedCameraHeight;
  final double cameraHeightMeters;
  final double vehicleWidthMeters;
  final double cameraLateralDisplacementMeters;

  final DashCamAlertLevel forwardCollision;
  final DashCamAlertLevel dangerousHeadway;
  final DashCamAlertLevel stopAndGo;
  final DashCamAlertLevel laneDepartureSolid;
  final DashCamAlertLevel laneDepartureDashed;
  final DashCamAlertLevel trafficSignRecognition;

  static const int unlimitedVideoSizeMinutes = 0;

  DashCamSettings copyWith({
    bool? recordingEnabled,
    int? videoSizeMinutes,
    bool? driverAssistanceEnabled,
    bool? fixedCameraHeight,
    double? cameraHeightMeters,
    double? vehicleWidthMeters,
    double? cameraLateralDisplacementMeters,
    DashCamAlertLevel? forwardCollision,
    DashCamAlertLevel? dangerousHeadway,
    DashCamAlertLevel? stopAndGo,
    DashCamAlertLevel? laneDepartureSolid,
    DashCamAlertLevel? laneDepartureDashed,
    DashCamAlertLevel? trafficSignRecognition,
  }) {
    return DashCamSettings(
      recordingEnabled: recordingEnabled ?? this.recordingEnabled,
      videoSizeMinutes: videoSizeMinutes ?? this.videoSizeMinutes,
      driverAssistanceEnabled:
          driverAssistanceEnabled ?? this.driverAssistanceEnabled,
      fixedCameraHeight: fixedCameraHeight ?? this.fixedCameraHeight,
      cameraHeightMeters: cameraHeightMeters ?? this.cameraHeightMeters,
      vehicleWidthMeters: vehicleWidthMeters ?? this.vehicleWidthMeters,
      cameraLateralDisplacementMeters: cameraLateralDisplacementMeters ??
          this.cameraLateralDisplacementMeters,
      forwardCollision: forwardCollision ?? this.forwardCollision,
      dangerousHeadway: dangerousHeadway ?? this.dangerousHeadway,
      stopAndGo: stopAndGo ?? this.stopAndGo,
      laneDepartureSolid: laneDepartureSolid ?? this.laneDepartureSolid,
      laneDepartureDashed: laneDepartureDashed ?? this.laneDepartureDashed,
      trafficSignRecognition:
          trafficSignRecognition ?? this.trafficSignRecognition,
    );
  }

  Map<String, dynamic> toJson() => {
        'recordingEnabled': recordingEnabled,
        'videoSizeMinutes': videoSizeMinutes,
        'driverAssistanceEnabled': driverAssistanceEnabled,
        'fixedCameraHeight': fixedCameraHeight,
        'cameraHeightMeters': cameraHeightMeters,
        'vehicleWidthMeters': vehicleWidthMeters,
        'cameraLateralDisplacementMeters': cameraLateralDisplacementMeters,
        'forwardCollision': forwardCollision.name,
        'dangerousHeadway': dangerousHeadway.name,
        'stopAndGo': stopAndGo.name,
        'laneDepartureSolid': laneDepartureSolid.name,
        'laneDepartureDashed': laneDepartureDashed.name,
        'trafficSignRecognition': trafficSignRecognition.name,
      };

  String serialize() => jsonEncode(toJson());

  static DashCamAlertLevel _levelOr(dynamic raw, DashCamAlertLevel fallback) {
    if (raw is! String) return fallback;
    for (final level in DashCamAlertLevel.values) {
      if (level.name == raw) return level;
    }
    return fallback;
  }

  static double _numOr(dynamic raw, double fallback) {
    if (raw is num) return raw.toDouble();
    return fallback;
  }

  static int _intOr(dynamic raw, int fallback) {
    if (raw is num) return raw.toInt();
    return fallback;
  }

  factory DashCamSettings.deserialize(String raw) {
    const fallback = DashCamSettings();
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return DashCamSettings(
        recordingEnabled:
            json['recordingEnabled'] as bool? ?? fallback.recordingEnabled,
        videoSizeMinutes:
            _intOr(json['videoSizeMinutes'], fallback.videoSizeMinutes),
        driverAssistanceEnabled: json['driverAssistanceEnabled'] as bool? ??
            fallback.driverAssistanceEnabled,
        fixedCameraHeight:
            json['fixedCameraHeight'] as bool? ?? fallback.fixedCameraHeight,
        cameraHeightMeters:
            _numOr(json['cameraHeightMeters'], fallback.cameraHeightMeters)
                .clamp(1.0, 3.0)
                .toDouble(),
        vehicleWidthMeters:
            _numOr(json['vehicleWidthMeters'], fallback.vehicleWidthMeters)
                .clamp(1.0, 3.0)
                .toDouble(),
        cameraLateralDisplacementMeters: _numOr(
                json['cameraLateralDisplacementMeters'],
                fallback.cameraLateralDisplacementMeters)
            .clamp(-1.0, 1.0)
            .toDouble(),
        forwardCollision:
            _levelOr(json['forwardCollision'], fallback.forwardCollision),
        dangerousHeadway:
            _levelOr(json['dangerousHeadway'], fallback.dangerousHeadway),
        stopAndGo: _levelOr(json['stopAndGo'], fallback.stopAndGo),
        laneDepartureSolid:
            _levelOr(json['laneDepartureSolid'], fallback.laneDepartureSolid),
        laneDepartureDashed:
            _levelOr(json['laneDepartureDashed'], fallback.laneDepartureDashed),
        trafficSignRecognition: _levelOr(
            json['trafficSignRecognition'], fallback.trafficSignRecognition),
      );
    } catch (_) {
      return fallback;
    }
  }
}
