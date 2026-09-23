import 'dart:math' as math;

/// منشأ سرعتی که به کالمن و سرعت‌سنج تحویل داده می‌شود.
enum SpeedSource { gnss, positionDelta, stationary }

/// نتیجهٔ یک اندازه‌گیری سرعت.
class SpeedEstimate {
  const SpeedEstimate(this.metersPerSecond, this.source);

  final double metersPerSecond;
  final SpeedSource source;
}

/// سرعت GNSS منبع اصلی سرعت‌سنج است. بعضی providerهای Fused، خصوصاً در شروع
/// یا پس از resume، موقعیت تازه می‌دهند اما مقدار speed را صفر گزارش می‌کنند.
/// این کلاس فقط در آن حالت از جابه‌جایی واقعی بین دو فیکس استفاده می‌کند.
///
/// شتاب‌سنج و ژیروسکوپ برای تخمین مستقیم سرعت وارد نمی‌شوند: انتگرال‌گیری از
/// آن‌ها در گوشی مصرفی در چند ثانیه drift قابل‌توجه می‌سازد. LocationService
/// تنها از آن‌ها برای تنظیم نویز فرایند کالمن و پایداری مسیر استفاده می‌کند.
class SpeedFusion {
  static const double _movingGnssFloorMs = 0.8;
  static const double _maxPlausibleSpeedMs = 70.0;

  double? _lastLatitude;
  double? _lastLongitude;
  int? _lastTimestampMs;

  void reset() {
    _lastLatitude = null;
    _lastLongitude = null;
    _lastTimestampMs = null;
  }

  SpeedEstimate measure({
    required double latitude,
    required double longitude,
    required int timestampMs,
    required double gnssSpeedMs,
    required double accuracyMeters,
  }) {
    final derived = _derivePositionSpeed(
      latitude: latitude,
      longitude: longitude,
      timestampMs: timestampMs,
      accuracyMeters: accuracyMeters,
    );

    // مقدار معتبر داپلر/GNSS در حرکت از جابه‌جایی مختصات دقیق‌تر است.
    if (gnssSpeedMs.isFinite &&
        gnssSpeedMs >= _movingGnssFloorMs &&
        gnssSpeedMs <= _maxPlausibleSpeedMs) {
      return SpeedEstimate(gnssSpeedMs, SpeedSource.gnss);
    }

    // موقعیت تنها زمانی جایگزین سرعت می‌شود که جابه‌جایی از دقت GPS بزرگ‌تر
    // باشد؛ بنابراین jitter، سرعت ساختگی تولید نمی‌کند.
    if (derived != null) {
      return SpeedEstimate(derived, SpeedSource.positionDelta);
    }
    return const SpeedEstimate(0, SpeedSource.stationary);
  }

  double? _derivePositionSpeed({
    required double latitude,
    required double longitude,
    required int timestampMs,
    required double accuracyMeters,
  }) {
    final lastLat = _lastLatitude;
    final lastLng = _lastLongitude;
    final lastTs = _lastTimestampMs;
    _lastLatitude = latitude;
    _lastLongitude = longitude;
    _lastTimestampMs = timestampMs;

    if (lastLat == null || lastLng == null || lastTs == null) return null;
    final deltaMs = timestampMs - lastTs;
    if (deltaMs < 400 || deltaMs > 5000) return null;

    final distance = _distanceMeters(lastLat, lastLng, latitude, longitude);
    final safeAccuracy =
        accuracyMeters.isFinite && accuracyMeters > 0 ? accuracyMeters : 15.0;
    // حداقل چهار متر برای حذف jitter و حداکثر هشت متر تا آغاز حرکت خودرو با
    // دقت معمول GPS بی‌دلیل پنهان نشود.
    final minimumDistance = math.max(4.0, math.min(safeAccuracy * 0.6, 8.0));
    if (distance < minimumDistance) return null;

    final speed = distance / (deltaMs / 1000.0);
    if (!speed.isFinite ||
        speed < _movingGnssFloorMs ||
        speed > _maxPlausibleSpeedMs) {
      return null;
    }
    return speed;
  }

  static double _distanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadius = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}
