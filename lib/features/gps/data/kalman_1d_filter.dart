import 'dart:math' as math;

/// فیلتر کالمن یک‌بعدیِ ساده (اسکالر) — روی هر محور (lat، lng، یا speed)
/// مستقل اجرا می‌شود. پیاده‌سازیِ فعلاً فعالِ [LocationService] (به‌جای
/// [JointKalmanFilter2D] که کوواریانسِ مشترکِ x-vx/y-vy را مدل می‌کند).
///
/// قبلاً به‌صورت یک کلاسِ خصوصی (`_Kalman1D`) داخل `location_service.dart`
/// بود؛ برای این‌که بتوان آن را مستقل از Geolocator/پلتفرم و در کنارِ
/// [JointKalmanFilter2D] مقایسه کرد (به `test/features/gps/`
/// `kalman_filter_comparison_test.dart` نگاه کنید)، به این فایلِ عمومی
/// منتقل شد. رفتار بدون تغییر است.
class Kalman1D {
  double? _value;
  double _variance = -1;
  int? _lastTimestampMs;

  final double processNoisePerSecond;

  final double minMeasurementAccuracy;

  Kalman1D(
      {required this.processNoisePerSecond, this.minMeasurementAccuracy = 1.0});

  double get value => _value ?? 0;
  double get uncertainty => _variance < 0 ? 0 : math.sqrt(_variance);

  void reset() {
    _value = null;
    _variance = -1;
    _lastTimestampMs = null;
  }

  double process(
    double measurement,
    double measurementAccuracy,
    int timestampMs, {
    double extraProcessNoise = 0,
  }) {
    final acc = math.max(measurementAccuracy, minMeasurementAccuracy);
    final measurementVariance = acc * acc;

    if (_value == null || _variance < 0) {
      _value = measurement;
      _variance = measurementVariance;
      _lastTimestampMs = timestampMs;
      return _value!;
    }

    final dtSec = math.max(
        (timestampMs - (_lastTimestampMs ?? timestampMs)) / 1000.0, 0.0);
    _lastTimestampMs = timestampMs;

    if (dtSec > 0) {
      final totalNoise = processNoisePerSecond + extraProcessNoise;
      _variance += dtSec * totalNoise * totalNoise;
    }

    final kalmanGain = _variance / (_variance + measurementVariance);
    _value = _value! + kalmanGain * (measurement - _value!);
    _variance = (1 - kalmanGain) * _variance;
    return _value!;
  }
}
