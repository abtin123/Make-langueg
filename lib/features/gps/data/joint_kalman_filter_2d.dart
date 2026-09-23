import 'dart:math' as math;

/// یک نمونه خام یا هموارشده از موقعیت خودرو، برای تغذیه یا خروجی فیلتر کالمن.
class KalmanLocationSample {
  final double latitude;
  final double longitude;
  final double speedMs;
  final double bearingDeg;
  final double accuracyMeters;

  /// دقتِ اندازه‌گیری سرعت، بر حسب m/s. این مقدار باید مستقل از accuracy
  /// مکانی باشد؛ گیرنده می‌تواند مختصات دقیق ولی سرعت بسیار نویزی بدهد.
  final double speedAccuracyMs;
  final int timestampMs;

  const KalmanLocationSample({
    required this.latitude,
    required this.longitude,
    required this.speedMs,
    required this.bearingDeg,
    required this.accuracyMeters,
    this.speedAccuracyMs = 2.5,
    required this.timestampMs,
  });
}

/// فیلتر کالمن دوبعدیِ *مشترک* با بردار حالت [x, y, vx, vy].
///
/// برخلاف دو فیلتر کالمن یک‌بعدیِ مستقل روی lat/lng (که پروژه فعلاً استفاده
/// می‌کند)، این نسخه موقعیت و سرعت را در یک ماتریس کوواریانس ۴×۴ با جمله‌های
/// متقاطع x-vx و y-vy مدل می‌کند. نتیجه: پیش‌بینیِ حرکت بین دو fix با توجه به
/// سرعت لحظه‌ای انجام می‌شود (نه فقط میان‌یابی ساده)، که به‌خصوص در پیچ‌ها و
/// شتاب‌گیری/ترمزگیری، مسیر هموارتر و واقعی‌تری تولید می‌کند.
///
/// پورت‌شده از KalmanFilter2D.kt (پروژه علی) به Dart، با محاسبات بر حسب متر
/// در یک قاب مختصات محلی (نسبت به اولین fix) تا از مشکل ناهم‌واحدی
/// درجه/متر که در فیلتر فعلی رفع شده بود، دوباره رخ ندهد.
class JointKalmanFilter2D {
  JointKalmanFilter2D({
    this.processNoiseQ = 2.0,
    this.measurementNoiseMultiplier = 1.0,
  });

  /// نویز فرآیند Q — هرچه بزرگ‌تر، فیلتر سریع‌تر به حرکت واقعی واکنش نشان
  /// می‌دهد ولی نویز بیشتری از GPS خام رد می‌کند.
  double processNoiseQ;

  /// ضریب نویز اندازه‌گیری R — هرچه بزرگ‌تر، فیلتر کمتر به هر fix تازه اعتماد
  /// می‌کند و بیشتر به مدل حرکتی خودش تکیه می‌کند.
  double measurementNoiseMultiplier;

  static const double earthRadiusMeters = 6371000.0;

  bool _initialized = false;
  double _refLat = 0;
  double _refLng = 0;
  int _lastTimestampMs = 0;
  double _lastBearingDeg = 0;

  // بردار حالت [x, y, vx, vy] بر حسب متر و متر بر ثانیه.
  double _x = 0, _y = 0, _vx = 0, _vy = 0;

  // ماتریس کوواریانس ۴×۴.
  final List<List<double>> _p = List.generate(4, (_) => List.filled(4, 0.0));

  /// مجموع فاصله‌ی لرزش GPS خام که این فیلتر حذف کرده (متر) — برای دیاگنوستیک.
  double totalJitterReducedMeters = 0;

  void reset() {
    _initialized = false;
    _refLat = 0;
    _refLng = 0;
    _lastTimestampMs = 0;
    _lastBearingDeg = 0;
    _x = _y = _vx = _vy = 0;
    totalJitterReducedMeters = 0;
    for (var i = 0; i < 4; i++) {
      for (var j = 0; j < 4; j++) {
        _p[i][j] = (i == j) ? 10.0 : 0.0;
      }
    }
  }

  void updateSettings({double? processNoise, double? noiseMultiplier}) {
    if (processNoise != null) processNoiseQ = math.max(processNoise, 0.1);
    if (noiseMultiplier != null) {
      measurementNoiseMultiplier = math.max(noiseMultiplier, 0.1);
    }
  }

  /// یک fix خام GPS را پردازش کرده و نمونه‌ی هموارشده را برمی‌گرداند.
  KalmanLocationSample process(
    KalmanLocationSample raw, {
    bool includeVelocity = true,
    double extraProcessNoise = 0.0,
  }) {
    if (!_initialized) {
      _refLat = raw.latitude;
      _refLng = raw.longitude;
      _x = 0;
      _y = 0;
      final bearingRad = raw.bearingDeg * math.pi / 180.0;
      _vx = raw.speedMs * math.sin(bearingRad);
      _vy = raw.speedMs * math.cos(bearingRad);
      _lastTimestampMs = raw.timestampMs;
      _lastBearingDeg = raw.bearingDeg;
      _initialized = true;

      final acc = math.max(raw.accuracyMeters, 1.0);
      _p[0][0] = acc * acc;
      _p[1][1] = acc * acc;
      _p[2][2] = 2.0;
      _p[3][3] = 2.0;
      return raw;
    }

    // A prediction tick can run slightly ahead of the timestamp carried by the
    // next GPS fix. Treating that fix as a fresh 100 ms sample (the old clamp)
    // artificially changes the velocity state and can create a visible speed
    // spike. Small timestamp skew is therefore processed with dt=0; genuinely
    // stale fixes are ignored.
    final timestampDeltaMs = raw.timestampMs - _lastTimestampMs;
    if (timestampDeltaMs < -250) {
      return _sampleFromState(_lastTimestampMs,
          fallbackBearingDeg: raw.bearingDeg);
    }
    final dt = (timestampDeltaMs / 1000.0).clamp(0.0, 10.0);
    if (dt > 0) {
      _lastTimestampMs = raw.timestampMs;
    }

    // ۱) مرحله‌ی پیش‌بینی (Predict)
    _predict(dt, extraProcessNoise: extraProcessNoise);

    // ۲) مرحله‌ی به‌روزرسانی با اندازه‌گیری (Update)
    final rawX = _lngToMeters(raw.longitude, _refLat, _refLng);
    final rawY = _latToMeters(raw.latitude, _refLat);

    final bearingRad = raw.bearingDeg * math.pi / 180.0;
    final rawVx = raw.speedMs * math.sin(bearingRad);
    final rawVy = raw.speedMs * math.cos(bearingRad);

    final baseAccuracy =
        math.max(raw.accuracyMeters, 1.0) * measurementNoiseMultiplier;
    final rPos = baseAccuracy * baseAccuracy;
    // موقعیت شبکه‌ای (Wi‑Fi/دکل) معمولاً سرعت و heading قابل اتکایی ندارد.
    // با نویز بسیار بزرگ، تنها مختصات آن وارد update می‌شود و بردار سرعتِ
    // تخمین‌زده‌شده از آخرین GPS معتبر دست‌نخورده می‌ماند.
    final speedSigma = math.max(
      raw.speedAccuracyMs.isFinite && raw.speedAccuracyMs > 0
          ? raw.speedAccuracyMs
          : 2.5,
      0.75,
    );
    final rVel = includeVelocity ? speedSigma * speedSigma : 1e12;

    final innovX = rawX - _x;
    final innovY = rawY - _y;
    final innovVx = rawVx - _vx;
    final innovVy = rawVy - _vy;

    // گیرنده‌های GPS در محیط شهری گاهی یک fix پرت با accuracy ظاهراً خوب
    // گزارش می‌کنند. فیلتر معمولی بخشی از آن را می‌پذیرد و همان بخش برای
    // نشانگر خودرو به‌صورت جهش قابل رؤیت است. به‌جای رد قطعی (که می‌تواند
    // تغییر واقعی مسیر را هم نادیده بگیرد)، R را متناسب با بزرگی نوآوری
    // افزایش می‌دهیم؛ بنابراین نمونهٔ پرت اثر بسیار کمی دارد، اما اگر یک
    // مختصات جدید در فیکس‌های بعدی تأیید شود فیلتر به‌تدریج به آن می‌رسد.
    final positionInnovationM = math.sqrt(innovX * innovX + innovY * innovY);
    final predictedPositionSigmaM = math.sqrt(
      math.max(_p[0][0], 0) + math.max(_p[1][1], 0) + 2 * rPos,
    );
    final positionGateM = math.max(35.0, predictedPositionSigmaM * 4.0);
    final effectiveRPos = _inflateMeasurementNoise(
      rPos,
      innovationMagnitude: positionInnovationM,
      gateMagnitude: positionGateM,
    );

    final velocityInnovationMs =
        math.sqrt(innovVx * innovVx + innovVy * innovVy);
    // 8 m/s (حدود 29 km/h) حداقلِ سخاوتمندانه‌ای برای تغییر یک‌ثانیه‌ای
    // سرعت است؛ بیشتر از این فقط نویز یک فیکس است مگر آن‌که دقت سرعت نیز
    // متناسباً پایین گزارش شود.
    final velocityGateMs = math.max(8.0, speedSigma * 4.0);
    final effectiveRVel = includeVelocity
        ? _inflateMeasurementNoise(
            rVel,
            innovationMagnitude: velocityInnovationMs,
            gateMagnitude: velocityGateMs,
          )
        : rVel;

    // به‌روزرسانیِ کامل کالمن با گِینِ ماتریسیِ ۲×۲ برای هر محور، به‌جای
    // گِینِ اسکالر/قطری. چون H (ماتریس اندازه‌گیری) واحد است — یعنی هم
    // موقعیت و هم سرعت مستقیماً اندازه‌گیری می‌شوند — معادله‌ی استاندارد
    // کالمن به‌صورت زیر ساده می‌شود:
    //   S = P + R
    //   K = P · S⁻¹
    //   x = x + K·y   (y = نوآوری/innovation)
    //   P = (I − K) · P
    // برخلاف نسخه‌ی قبلی که فقط عناصر قطریِ P را در نظر می‌گرفت (و عملاً
    // جمله‌های متقاطعِ x-vx و y-vy را در همان مرحله‌ی پیش‌بینی محاسبه ولی در
    // مرحله‌ی به‌روزرسانی نادیده می‌گرفت)، اینجا کل بلوکِ ۲×۲ به‌درستی
    // معکوس و اعمال می‌شود. محورهای x/y از هم مستقل‌اند (بدون جمله‌ی
    // متقاطعِ x-y)، پس این کار به دو مسئله‌ی مستقلِ ۲×۲ تقسیم می‌شود.
    _updateAxisBlock(
      innovPos: innovX,
      innovVel: innovVx,
      rPos: effectiveRPos,
      rVel: effectiveRVel,
      pIndexPos: 0,
      pIndexVel: 2,
      applyState: (dPos, dVel) {
        _x += dPos;
        _vx += dVel;
      },
    );

    _updateAxisBlock(
      innovPos: innovY,
      innovVel: innovVy,
      rPos: effectiveRPos,
      rVel: effectiveRVel,
      pIndexPos: 1,
      pIndexVel: 3,
      applyState: (dPos, dVel) {
        _y += dPos;
        _vy += dVel;
      },
    );

    if (raw.speedMs >= 0.5) _lastBearingDeg = raw.bearingDeg;
    final output = _sampleFromState(
      raw.timestampMs,
      fallbackBearingDeg: raw.bearingDeg,
    );
    final rawDist = math.sqrt(innovX * innovX + innovY * innovY);
    final filterDx = _lngToMeters(output.longitude, _refLat, _refLng) - rawX;
    final filterDy = _latToMeters(output.latitude, _refLat) - rawY;
    final filterDist = math.sqrt(filterDx * filterDx + filterDy * filterDy);
    totalJitterReducedMeters += math.max(0.0, rawDist - filterDist);
    return output;
  }

  /// Applies a position-only measurement without allowing an unreliable
  /// Wi-Fi/cell fix to modify the velocity state. This is intentionally
  /// separate from [process], because network location has no trustworthy
  /// speed/heading measurement.
  KalmanLocationSample processPositionOnly(KalmanLocationSample raw) {
    if (!_initialized) return process(raw, includeVelocity: false);
    final savedVx = _vx;
    final savedVy = _vy;
    process(raw, includeVelocity: false);
    _vx = savedVx;
    _vy = savedVy;
    return _sampleFromState(raw.timestampMs);
  }

  /// مقدار R را برای نوآوری بزرگ افزایش می‌دهد. سقف 64× از واگرایی عددی
  /// جلوگیری می‌کند و در عین حال فیکس‌های پرت را از مسیر تصویری دور نگه
  /// می‌دارد. از مربع نسبت استفاده می‌شود چون R و کوواریانس برحسب واریانس‌اند.
  static double _inflateMeasurementNoise(
    double variance, {
    required double innovationMagnitude,
    required double gateMagnitude,
  }) {
    if (!innovationMagnitude.isFinite ||
        !gateMagnitude.isFinite ||
        gateMagnitude <= 0 ||
        innovationMagnitude <= gateMagnitude) {
      return variance;
    }
    final ratio = (innovationMagnitude / gateMagnitude).clamp(1.0, 8.0);
    return variance * ratio * ratio;
  }

  /// فقط مدل حرکت را جلو می‌برد و هیچ اندازه‌گیری GPS را وارد نمی‌کند. برای
  /// افت کوتاه سیگنال (مثل زیر پل یا تونل کوتاه) استفاده می‌شود؛ caller باید
  /// بازهٔ زمانی را محدود کند تا پیش‌بینیِ بدون GPS جای واقعیت را نگیرد.
  KalmanLocationSample? predictOnly(int timestampMs) {
    if (!_initialized || timestampMs <= _lastTimestampMs) return null;
    final dt = ((timestampMs - _lastTimestampMs) / 1000.0).clamp(0.01, 1.0);
    // Prediction advances the state clock. A later GPS fix whose own timestamp
    // is a little older is then processed with dt=0 instead of being given an
    // artificial 100 ms prediction step.
    _lastTimestampMs = timestampMs;
    _predict(dt);
    return _sampleFromState(timestampMs);
  }

  void _predict(double dt, {double extraProcessNoise = 0.0}) {
    _x += _vx * dt;
    _y += _vy * dt;

    final dt2 = dt * dt;
    final dt3 = dt2 * dt;
    final dt4 = dt3 * dt;
    // شتاب‌سنج مکان را به‌تنهایی تعیین نمی‌کند؛ شدت حرکت را به نویز مدل
    // وارد می‌کند تا کالمن هنگام شتاب‌گیری و ترمزگیری واقعی سریع‌تر واکنش دهد.
    final q = processNoiseQ + math.max(extraProcessNoise, 0.0);

    final q00 = q * dt4 / 4.0;
    final q02 = q * dt3 / 2.0;
    final q22 = q * dt2;

    _p[0][0] += 2 * dt * _p[0][2] + dt2 * _p[2][2] + q00;
    _p[0][2] += dt * _p[2][2] + q02;
    _p[2][0] = _p[0][2];
    _p[2][2] += q22;

    _p[1][1] += 2 * dt * _p[1][3] + dt2 * _p[3][3] + q00;
    _p[1][3] += dt * _p[3][3] + q02;
    _p[3][1] = _p[1][3];
    _p[3][3] += q22;
  }

  KalmanLocationSample _sampleFromState(
    int timestampMs, {
    double? fallbackBearingDeg,
  }) {
    final filteredLat = _metersToLat(_y, _refLat);
    final filteredLng = _metersToLng(_x, _refLat, _refLng);

    var filteredSpeedMs = math.sqrt(_vx * _vx + _vy * _vy);
    var filteredBearing = math.atan2(_vx, _vy) * 180.0 / math.pi;
    if (filteredBearing < 0) filteredBearing += 360;

    final estimatedErr = math.sqrt(_p[0][0] + _p[1][1]);

    return KalmanLocationSample(
      latitude: filteredLat,
      longitude: filteredLng,
      speedMs: filteredSpeedMs < 0.2 ? 0 : filteredSpeedMs,
      bearingDeg: filteredSpeedMs < 0.5
          ? (fallbackBearingDeg ?? _lastBearingDeg)
          : filteredBearing,
      accuracyMeters: math.max(estimatedErr, 1.0),
      timestampMs: timestampMs,
    );
  }

  /// یک مرحله‌ی به‌روزرسانیِ کالمنِ کامل برای بلوکِ ۲×۲ یک محور (مثلاً
  /// [x, vx] یا [y, vy]) با گِینِ ماتریسی — نه اسکالر.
  ///
  /// [pIndexPos] و [pIndexVel] اندیس‌های موقعیت/سرعت در ماتریس کوواریانسِ
  /// ۴×۴ اصلی [_p] هستند (۰و۲ برای محور x، ۱و۳ برای محور y).
  /// [applyState] افزایشِ حالت (Δموقعیت، Δسرعت) را روی بردار حالتِ اصلی
  /// اعمال می‌کند.
  void _updateAxisBlock({
    required double innovPos,
    required double innovVel,
    required double rPos,
    required double rVel,
    required int pIndexPos,
    required int pIndexVel,
    required void Function(double dPos, double dVel) applyState,
  }) {
    final p00 = _p[pIndexPos][pIndexPos];
    final p01 = _p[pIndexPos][pIndexVel];
    final p10 = _p[pIndexVel][pIndexPos];
    final p11 = _p[pIndexVel][pIndexVel];

    // S = H·P·Hᵀ + R ، با H = I پس S = P + R (فقط قطرِ R چون نویزِ
    // اندازه‌گیریِ موقعیت و سرعت مستقل فرض شده‌اند؛ عناصرِ نامتقارنِ P دست
    // نخورده باقی می‌مانند).
    final s00 = p00 + rPos;
    final s01 = p01;
    final s10 = p10;
    final s11 = p11 + rVel;

    final det = s00 * s11 - s01 * s10;
    if (det.abs() < 1e-12) {
      // ماتریسِ منفرد (نظری، عملاً تقریباً هرگز رخ نمی‌دهد) — از
      // به‌روزرسانی صرف‌نظر می‌کنیم تا از تقسیم بر صفر جلوگیری شود.
      return;
    }
    final invDet = 1.0 / det;
    final sInv00 = s11 * invDet;
    final sInv01 = -s01 * invDet;
    final sInv10 = -s10 * invDet;
    final sInv11 = s00 * invDet;

    // K = P · S⁻¹  (۲×۲ · ۲×۲)
    final k00 = p00 * sInv00 + p01 * sInv10;
    final k01 = p00 * sInv01 + p01 * sInv11;
    final k10 = p10 * sInv00 + p11 * sInv10;
    final k11 = p10 * sInv01 + p11 * sInv11;

    // به‌روزرسانیِ حالت: Δ = K · نوآوری
    final dPos = k00 * innovPos + k01 * innovVel;
    final dVel = k10 * innovPos + k11 * innovVel;
    applyState(dPos, dVel);

    // به‌روزرسانیِ کوواریانس: P = (I − K) · P
    final a00 = 1.0 - k00;
    final a01 = -k01;
    final a10 = -k10;
    final a11 = 1.0 - k11;

    final newP00 = a00 * p00 + a01 * p10;
    final newP01 = a00 * p01 + a01 * p11;
    final newP10 = a10 * p00 + a11 * p10;
    final newP11 = a10 * p01 + a11 * p11;

    // برای اطمینان از تقارنِ عددیِ P (خطاهای گِردکردنِ اعشاری می‌توانند
    // newP01 و newP10 را کمی نامتقارن کنند)، میانگین می‌گیریم.
    final symmetricOffDiag = (newP01 + newP10) / 2.0;

    _p[pIndexPos][pIndexPos] = newP00;
    _p[pIndexPos][pIndexVel] = symmetricOffDiag;
    _p[pIndexVel][pIndexPos] = symmetricOffDiag;
    _p[pIndexVel][pIndexVel] = newP11;
  }

  static double _latToMeters(double lat, double refLat) =>
      (lat - refLat) * math.pi / 180.0 * earthRadiusMeters;

  static double _lngToMeters(double lng, double refLat, double refLng) {
    final radLat = refLat * math.pi / 180.0;
    return (lng - refLng) *
        math.pi /
        180.0 *
        earthRadiusMeters *
        math.cos(radLat);
  }

  static double _metersToLat(double metersY, double refLat) =>
      refLat + (metersY / earthRadiusMeters) * 180.0 / math.pi;

  static double _metersToLng(double metersX, double refLat, double refLng) {
    final radLat = refLat * math.pi / 180.0;
    final scale = math.cos(radLat);
    final effectiveScale = scale.abs() < 1e-6 ? 1.0 : scale;
    return refLng +
        (metersX / (earthRadiusMeters * effectiveScale)) * 180.0 / math.pi;
  }
}
