import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'joint_kalman_filter_2d.dart';
import 'kalman_1d_filter.dart';
import 'speed_fusion.dart';

enum LocationState { waiting, active, unavailable }

class VehiclePosition {
  final double lat;
  final double lng;
  final double headingDeg;
  final double speedKmh;
  final double accuracyM;

  /// true یعنی این نمونه از پیش‌بینی یا موقعیت کمکی شبکه آمده است، نه فیکس
  /// دقیق GPS. UI و کنترلر تونل می‌توانند رفتار محافظه‌کارانه داشته باشند.
  final bool isEstimated;

  const VehiclePosition({
    required this.lat,
    required this.lng,
    required this.headingDeg,
    required this.speedKmh,
    required this.accuracyM,
    this.isEstimated = false,
  });
}

/// وضعیت لحظه‌ای دیاگنوستیک فیلتر کالمن مشترک، برای نمایش در صفحه‌ی تنظیمات
/// (مقایسه‌ی GPS خام با خروجی هموارشده و مقدار نویز حذف‌شده).
class JointKalmanDiagnostics {
  final bool enabled;
  final KalmanLocationSample? raw;
  final KalmanLocationSample? filtered;
  final double totalJitterReducedMeters;
  final double processNoiseQ;
  final double measurementNoiseMultiplier;

  const JointKalmanDiagnostics({
    required this.enabled,
    required this.raw,
    required this.filtered,
    required this.totalJitterReducedMeters,
    required this.processNoiseQ,
    required this.measurementNoiseMultiplier,
  });

  JointKalmanDiagnostics copyWith({
    bool? enabled,
    KalmanLocationSample? raw,
    KalmanLocationSample? filtered,
    double? totalJitterReducedMeters,
    double? processNoiseQ,
    double? measurementNoiseMultiplier,
  }) {
    return JointKalmanDiagnostics(
      enabled: enabled ?? this.enabled,
      raw: raw ?? this.raw,
      filtered: filtered ?? this.filtered,
      totalJitterReducedMeters:
          totalJitterReducedMeters ?? this.totalJitterReducedMeters,
      processNoiseQ: processNoiseQ ?? this.processNoiseQ,
      measurementNoiseMultiplier:
          measurementNoiseMultiplier ?? this.measurementNoiseMultiplier,
    );
  }
}

class LocationService {
  final _controller = StreamController<VehiclePosition>.broadcast();
  StreamSubscription<Position>? _sub;
  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  // --- بازیابی خودکار پس از خطا ------------------------------------------
  // باگ قبلی: getPositionStream().listen(..., onError: (_) {}) هر خطای
  // پلتفرمی (مثلاً «location provider is not available»، کشته‌شدن سرویس
  // توسط بهینه‌سازهای باتریِ سازنده‌ی گوشی، یا هر PlatformException دیگر)
  // را کاملاً بی‌صدا می‌بلعید. نتیجه: استریم برای همیشه می‌مرد، هیچ فیکس
  // جدیدی نمی‌رسید، readinessProvider هم چون permission/service هنوز
  // ready بودند بنر خطا نشان نمی‌داد — یعنی کاربر می‌ماند با یک نقشه که
  // برای همیشه منتظرِ GPS است بدون هیچ نشانه‌ای از این‌که چیزی خراب شده.
  // حالا خطا لاگ می‌شود و استریم با backoff نمایی (حداکثر ۱۰ ثانیه) خودش
  // را دوباره وصل می‌کند.
  bool _disposed = false;
  int _restartAttempts = 0;
  Timer? _restartTimer;
  DateTime? _startedAt;
  bool _gotFirstFix = false;

  // هر start یک نسل مستقل از درخواست‌های bootstrap دارد. پاسخِ دیررسِ
  // getLastKnownPosition/getCurrentPosition از نسل قبلی نباید بعد از stop یا
  // شروع دوباره، نشانگر را به مختصات قدیمی برگرداند.
  int _runId = 0;
  int? _lastGpsMeasurementTsMs;
  double? _lastAcceptedRawLat;
  double? _lastAcceptedRawLng;
  int? _lastAcceptedRawTsMs;
  double? _lastAcceptedRawSpeedMs;

  static const int _unavailableAfterAttempts = 4;

  LocationState _state = LocationState.waiting;
  LocationState get state => _state;
  final _stateController = StreamController<LocationState>.broadcast();
  Stream<LocationState> get stateStream => _stateController.stream;

  void _setState(LocationState next) {
    if (_state == next) return;
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }

  // --- واچ‌داگِ «بدون فیکس، بدون خطا» ------------------------------------
  // باگ واقعی: getPositionStream روی بعضی گوشی‌ها/شرایط (مثلاً وقتی
  // FusedLocationProviderClient سرویسش رو از دست می‌ده ولی اون رو به‌عنوان
  // PlatformException گزارش نمی‌کنه) کاملاً ساکت می‌مونه — نه فیکس می‌ده نه
  // خطا. backoff بالا فقط رو onError واکنش نشون می‌ده، پس این حالت رو
  // اصلاً تشخیص نمی‌داد و کاربر تا ابد با «تلاش شماره ۱» و هیچ فیکسی
  // می‌موند، مگر این‌که دستی روی بنر «تلاش دوباره» می‌زد (دقیقاً چیزی که
  // توی لاگ دیده شد: ۲ دقیقه سکوت کامل بین شروع و تپ دستی کاربر). حالا
  // اگه ظرف ۱۲ ثانیه از start() هیچ فیکسی نرسه، بدون نیاز به خطا یا تپ
  // کاربر، خودکار با همون backoff نمایی دوباره وصل می‌شود.
  Timer? _noFixWatchdog;

  // Fused معمولاً باید در چند ثانیه داده بدهد؛ اما LocationManager خام در
  // شروع سرد ممکن است چند ده ثانیه برای قفل ماهواره وقت بخواهد. timeout یکسان
  // ۱۲ ثانیه‌ای باعث می‌شد دقیقاً همان fallback خام پیش از اولین فیکس cancel و
  // از نو ساخته شود؛ بنابراین هرگز فرصت قفل‌کردن پیدا نمی‌کرد.
  static const Duration _fusedNoFixTimeout = Duration(seconds: 12);
  static const Duration _rawManagerNoFixTimeout = Duration(seconds: 45);

  Duration get _noFixTimeout =>
      _useRawLocationManager ? _rawManagerNoFixTimeout : _fusedNoFixTimeout;

  void _armNoFixWatchdog() {
    _noFixWatchdog?.cancel();
    final timeout = _noFixTimeout;
    final provider = _useRawLocationManager ? 'LocationManager خام' : 'Fused';
    _noFixWatchdog = Timer(timeout, () {
      if (_disposed || _gotFirstFix) return;
      
      _onStreamError('no-fix-timeout', isNoFixTimeout: true);
    });
  }

  double _accelBaseline = 0;
  double _accelJerk = 0;
  double _accelMotionNoise = 0;
  double _gyroAngularRate = 0;
  double _gyroMotionNoise = 0;

  // --- فیلتر کالمن مشترک (اختیاری) --------------------------------------
  // به‌جای دو فیلتر کالمن یک‌بعدیِ مستقل روی lat/lng، این فیلتر بردار حالت
  // [x, y, vx, vy] را با کوواریانس مشترک مدل می‌کند (پورت‌شده از پروژه علی).
  // فیلتر مشترک اکنون مسیر اصلی ناوبری است. نسخهٔ ۱بعدی فقط fallback داخلی
  // باقی می‌ماند؛ این‌گونه موقعیت و سرعت روی یک مدل دوبعدی مشترک فیلتر و
  // پیش‌بینی می‌شوند.
  bool useJointKalman = true;
  final _jointKalman = JointKalmanFilter2D();

  // در تونل یا زیر پل، GPS معمولاً چند فیکس را از دست می‌دهد یا با دقت بد
  // برمی‌گردد. پیش‌بینی فقط‌کالمن کوتاه و محدود است، نه جایگزین دائمی GPS.
  Timer? _gpsGapPredictionTimer;
  Timer? _networkAssistTimer;
  DateTime? _lastGpsFixAt;
  DateTime? _lastNetworkAssistAt;
  bool _networkAssistInFlight = false;
  bool _isPredictingGpsGap = false;
  double _lastPipelineSpeedKmh = 0;

  // GPS نقشه حداکثر هر یک ثانیه فیکس می‌دهد؛ اگر این آستانه از آن کوتاه‌تر
  // باشد، فاصلهٔ طبیعیِ بین دو فیکس واقعی هم «افت سیگنال» تشخیص داده می‌شود و
  // هر ۵۰۰ میلی‌ثانیه یک موقعیت تخمینی مصنوعی ساخته می‌شود — که به نوبهٔ خود
  // رفرش کامل ویوپورت (بازخوانی ABM + کوئری‌های سنگین) را با هر تیک راه
  // می‌اندازد و باعث هنگ شدید نقشه حین رانندگی می‌شود. آستانه باید همیشه
  // بیشتر از فاصلهٔ عادیِ فیکس واقعی باشد.
  static const Duration _gpsGapBeforePrediction = Duration(milliseconds: 1300);
  static const Duration _maxGpsPredictionGap = Duration(seconds: 8);
  static const Duration _networkAssistAfterGap = Duration(seconds: 3);
  static const Duration _networkAssistInterval = Duration(seconds: 10);

  final _jointKalmanDiagnosticsController =
      StreamController<JointKalmanDiagnostics>.broadcast();
  Stream<JointKalmanDiagnostics> get jointKalmanDiagnostics =>
      _jointKalmanDiagnosticsController.stream;

  void setJointKalmanEnabled(bool enabled) {
    useJointKalman = enabled;
    _jointKalman.reset();
  }

  void updateJointKalmanSettings(
      {double? processNoise, double? noiseMultiplier}) {
    _jointKalman.updateSettings(
      processNoise: processNoise,
      noiseMultiplier: noiseMultiplier,
    );
  }

  // --- Position filter -----------------------------------------------
  // Fixed before: lat/lng were fed straight into the Kalman filters in
  // *degrees*, while their accuracy (from the GPS) is in *meters* — those
  // two numbers differ by ~5 orders of magnitude, so the filter's variance
  // bookkeeping was meaningless and it ended up over-damping real movement
  // (most noticeable exactly where you'd notice it: mid-turn). We now
  // convert the measurement accuracy from meters to degrees before it
  // enters the filter, so the filtered value and its accuracy share the
  // same unit throughout.
  static const double _metersPerDegLat = 111320.0;

  double? _lastSentLat;
  double? _lastSentLng;

  final _xFilter = Kalman1D(processNoisePerSecond: 1.5);
  final _yFilter = Kalman1D(processNoisePerSecond: 1.5);
  final _speedFilter =
      Kalman1D(processNoisePerSecond: 0.8, minMeasurementAccuracy: 2.0);
  final _speedFusion = SpeedFusion();

  double? _smoothHeading;
  int? _lastHeadingTsMs;

  // Time-constant based smoothing (instead of a flat per-fix alpha) so the
  // heading catches up to a real turn within a fixed amount of *time*
  // regardless of how often fixes happen to arrive.
  static const double _headingTimeConstantSec = 0.65;
  static const double _headingFreezeSpeedKmh = 2.0;

  Stream<VehiclePosition> get stream => _controller.stream;

  void start() {
    _disposed = false;
    final runId = ++_runId;
    _restartTimer?.cancel();
    // Provider ممکن است بعد از بازگشت از تنظیمات مکان دوباره آماده شود؛ پیش از
    // اتصال جدید، listener قبلی را قطع می‌کنیم تا دو استریم GPS هم‌زمان
    // دوربین را به دو فیکس متفاوت نکشند.
    _sub?.cancel();
    _accelSub?.cancel();
    _gyroSub?.cancel();
    final settings = _buildLocationSettings();
    _lastSentLat = null;
    _lastSentLng = null;
    _xFilter.reset();
    _yFilter.reset();
    _speedFilter.reset();
    _speedFusion.reset();
    _jointKalman.reset();
    _lastGpsFixAt = null;
    _lastGpsMeasurementTsMs = null;
    _lastAcceptedRawLat = null;
    _lastAcceptedRawLng = null;
    _lastAcceptedRawTsMs = null;
    _lastAcceptedRawSpeedMs = null;
    _lastNetworkAssistAt = null;
    _networkAssistInFlight = false;
    _isPredictingGpsGap = false;
    _lastPipelineSpeedKmh = 0;
    _gpsGapPredictionTimer?.cancel();
    _networkAssistTimer?.cancel();
    _smoothHeading = null;
    _lastHeadingTsMs = null;
    _accelBaseline = 0;
    _accelJerk = 0;
    _accelMotionNoise = 0;
    _gyroAngularRate = 0;
    _gyroMotionNoise = 0;
    _startedAt = DateTime.now();
    _gotFirstFix = false;
    _setState(LocationState.waiting);
    
    unawaited(_logRuntimeProbe(runId));

    // این دو درخواست فقط برای نمایش سریع یک موقعیت تقریبی‌اند؛ هرگز وارد
    // کالمن/محاسبهٔ سرعت نمی‌شوند تا مختصات cache یا شبکه باعث پرش سرعت‌سنج
    // و جهت خودرو نشود.
    unawaited(_emitLastKnownPosition(runId));
    unawaited(_emitQuickInitialPosition(runId));

    // فیکس سریعِ موازی (شبیه رفتار گوگل‌مپ/گوگل‌ارث): به‌جای این‌که کاربر
    // منتظر بمونه تا استریمِ bestForNavigation قفلِ ماهواره‌ای کامل بگیره
    // (که می‌تونه ده‌ها ثانیه طول بکشه)، یک درخواستِ یک‌باره‌ی جدا با دقتِ
    // پایین‌تر (medium) می‌فرستیم که روی اکثر گوشی‌ها از Wi‌Fi/دکل در
    // ۱-۳ ثانیه جواب می‌ده. همین که این فیکسِ تقریبی رسید بلافاصله نمایش
    // داده می‌شه؛ استریمِ دقیقِ اصلی وقتی برسه (که همچنان دنبالش هستیم)
    // جایگزینش می‌کنه. این فیکسِ تقریبی هرگز برای مسیریابی استفاده نمی‌شه
    // چون فقط _controller رو تغذیه می‌کنه، نه _onPosition/فیلترها را.
    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) => _onPosition(position, runId),
      onError: (Object error, StackTrace stackTrace) =>
          _onStreamError(error, runId: runId),
      cancelOnError: false,
    );
    // GPS نقشه حداکثر هر یک ثانیه فیکس می‌دهد؛ نرخ game (۵۰Hz) برای دو
    // سنسور هیچ دقت قابل‌استفاده‌ای به marker اضافه نمی‌کرد و CPU پس‌زمینه را
    // بالا می‌برد. UI interval برای نویز/چرخش نرم کافی است.
    _accelSub = userAccelerometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen(_onAccel, onError: (_) {});
    _gyroSub = gyroscopeEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen(_onGyroscope, onError: (_) {});
    _gpsGapPredictionTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _predictGpsGap(),
    );
    _networkAssistTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _requestNetworkAssistIfNeeded(),
    );
    _armNoFixWatchdog();
  }

  /// ثبت مستقل پیش‌نیازهای واقعی GPS. این اطلاعات پیش از subscribe گرفته
  /// می‌شود تا در صورت silent شدن provider، گزارش قابل ارسال همچنان علت‌های
  /// سطح سیستم‌عامل (سرویس خاموش یا مجوز) را داشته باشد.
  Future<void> _logRuntimeProbe(int runId) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      final permission = await Geolocator.checkPermission();
      if (_disposed || runId != _runId) return;
      
    } catch (error) {
      if (_disposed || runId != _runId) return;
      
    }
  }

  /// خطای استریم موقعیت را (برخلاف قبل) لاگ می‌کند و با تأخیر فزاینده
  /// (۱، ۲، ۴... تا سقف ۱۰ ثانیه) دوباره وصل می‌شود، به‌جای این‌که برای
  /// همیشه ساکت بماند.

  Future<void> _emitLastKnownPosition(int runId) async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last == null || _disposed || runId != _runId || _gotFirstFix) return;

      final age = DateTime.now().difference(last.timestamp).inSeconds;
      // پنج دقیقه برای یک نشانگر ناوبری زمان زیادی است و می‌تواند در لحظهٔ
      // ورود به نقشه یک جهش مکانی گمراه‌کننده بسازد. کش فقط یک پیش‌نمایش کوتاه
      // برای جلوگیری از صفحهٔ خالی است.
      if (age > 90 || !_isValidCoordinate(last.latitude, last.longitude))
        return;

      

      _controller.add(VehiclePosition(
        lat: last.latitude,
        lng: last.longitude,
        headingDeg:
            last.heading.isFinite && last.heading >= 0 ? last.heading : 0,
        // سرعت cached ذاتاً قدیمی است؛ نمایش آن به‌عنوان سرعت زنده باعث جهش
        // آغازین سرعت‌سنج می‌شد، بنابراین عمداً صفر می‌ماند.
        speedKmh: 0,
        accuracyM:
            last.accuracy.isFinite && last.accuracy > 0 ? last.accuracy : 50,
        isEstimated: true,
      ));
    } catch (e) {
      
    }
  }

  Future<void> _emitQuickInitialPosition(int runId) async {
    try {
      final quick = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 6),
      );
      if (_disposed ||
          runId != _runId ||
          _gotFirstFix ||
          !_isValidCoordinate(quick.latitude, quick.longitude)) {
        return;
      }
      final accuracy = quick.accuracy.isFinite && quick.accuracy > 0
          ? quick.accuracy
          : 100.0;
      if (accuracy > 1000) return;
      
      _controller.add(VehiclePosition(
        lat: quick.latitude,
        lng: quick.longitude,
        headingDeg:
            quick.heading.isFinite && quick.heading >= 0 ? quick.heading : 0,
        speedKmh: 0,
        accuracyM: accuracy,
        isEstimated: true,
      ));
    } catch (error) {
      // فیکس اولیه صرفاً یک بهبود UX است؛ خطای آن نباید چرخهٔ GPS اصلی را
      // مختل یا دوباره‌راه‌اندازی کند، اما برای عیب‌یابی ثبت می‌شود.
      
    }
  }

  // باگ واقعیِ «فقط با فیلترشکن روشن پیدا می‌کنه»: پیش‌فرضِ geolocator روی
  // اندروید از FusedLocationProviderClient استفاده می‌کند که به Google Play
  // services متکی است. وقتی دسترسی به سرویس‌های گوگل (نه GPS خودِ گوشی)
  // مسدود/محدود است — دقیقاً چیزی که یک VPN/فیلترشکن دور می‌زند —
  // getPositionStream برای همیشه ساکت می‌ماند: نه خطا، نه فیکس (همان چیزی
  // که در لاگ دیده شد: getLastKnownPosition و coarse fix که مسیر جدایی
  // دارند کار می‌کنند، ولی استریمِ اصلی هرگز چیزی نمی‌دهد). بعد از چند
  // تلاشِ ناموفقِ پشت‌سرهم، به LocationManager خامِ اندروید (مستقیم روی
  // تراشه‌ی GPS/شبکه، بدون وابستگی به Play services) سوییچ می‌کنیم.
  // پس از نخستین timeout یا خطای Fused، سریع‌تر سراغ provider مستقل از
  // Play Services می‌رویم؛ انتظار دو چرخهٔ کامل، در عمل زمان دریافت را بی‌دلیل
  // افزایش می‌داد.
  static const int _fallbackToRawManagerAfterAttempts = 1;
  // Fused provider باید مسیر پیش‌فرض باشد تا اولین فیکس با کمک Wi‑Fi/دکل
  // سریع دریافت شود؛ LocationManager خام فقط fallback پس از شکست‌های پی‌درپی
  // است. مقدار true در نسخهٔ قبلی ناخواسته این fallback را از همان ابتدا
  // فعال می‌کرد.
  bool _useRawLocationManager = false;

  void _onStreamError(
    Object error, {
    int? runId,
    bool isNoFixTimeout = false,
  }) {
    // cancel در لایهٔ پلتفرم می‌تواند اندکی ناهم‌زمان باشد؛ خطاهای باقی‌مانده
    // از نسل قدیمی نباید استریم سالمِ تازه را دوباره راه‌اندازی کنند.
    if (runId != null && runId != _runId) return;
    
    if (_disposed) return;
    _restartAttempts++;
    if (!_useRawLocationManager &&
        _restartAttempts >= _fallbackToRawManagerAfterAttempts) {
      _useRawLocationManager = true;
      
    }
    // timeoutِ بدون خطا، خصوصاً در LocationManager خام و شروع سرد، به‌معنی
    // «سرویس در دسترس نیست» نیست. این حالت فقط چرخهٔ بازیابی را ادامه می‌دهد؛
    // unavailable برای خطاهای واقعی پلتفرم حفظ می‌شود.
    if (!_gotFirstFix &&
        !isNoFixTimeout &&
        _restartAttempts >= _unavailableAfterAttempts) {
      _setState(LocationState.unavailable);
    }
    final delaySec = math.min(1 << math.min(_restartAttempts, 4), 10);
    _restartTimer?.cancel();
    _restartTimer = Timer(Duration(seconds: delaySec), () {
      if (!_disposed) start();
    });
  }

  /// Real GPS chips report fixes at 1–10 Hz at best — nothing updates
  /// "every microsecond". What we *can* do is stop the OS from throttling
  /// updates to distance-only delivery and ask for the fastest sane
  /// interval, then lean on [VehiclePositionAnimator] (already interpolating
  /// at 60fps) to make the motion between those fixes look continuous.
  ///
  /// باگ واقعی که همین‌جا رفع شد: AndroidManifest از قبل مجوزهای لازم را
  /// داشت (ACCESS_BACKGROUND_LOCATION، FOREGROUND_SERVICE،
  /// FOREGROUND_SERVICE_LOCATION، POST_NOTIFICATIONS) ولی هیچ‌کدام واقعاً
  /// استفاده نمی‌شدند — چون AndroidSettings هیچ‌وقت
  /// foregroundNotificationConfig را تنظیم نمی‌کرد، geolocator هیچ‌وقت
  /// سرویسِ فورگراندِ واقعی را استارت نمی‌زد. نتیجه: به‌محضِ خاموش‌شدنِ
  /// صفحه یا رفتنِ اپ به پس‌زمینه، اندروید (Doze/App Standby) استریمِ
  /// موقعیت را طبقِ رفتارِ پیش‌فرضش قطع/تأخیر می‌انداخت — دقیقاً همان‌طور
  /// که حدس زده بودی. حالا با این تنظیم، یک نوتیفیکیشنِ دائمی («در حال
  /// ناوبری») نشان داده می‌شود و اندروید اپ را به‌عنوان یک سرویسِ فورگراند
  /// می‌شناسد که از Doze/بهینه‌سازیِ باتری معاف است.
  LocationSettings _buildLocationSettings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: const Duration(milliseconds: 250),
        forceLocationManager: _useRawLocationManager,
        // باگ واقعیِ «دیر پیدا شدن GPS»: قبلاً اینجا forceLocationManager: true
        // بود، یعنی geolocator به‌جای FusedLocationProviderClient (که با
        // ترکیب Wi-Fi/دکل/GPS خیلی سریع‌تر اولین فیکس را می‌دهد) از
        // LocationManager خامِ اندروید استفاده می‌کرد — که فقط به ماهواره
        // متکی است و اولین فیکس آن (به‌خصوص start سرد یا داخل ساختمان) ده‌ها
        // ثانیه یا چند دقیقه طول می‌کشد. حذفش می‌کنیم تا FusedLocationProviderClient
        // (پیش‌فرض) استفاده شود؛ دقتِ حین رانندگی همچنان bestForNavigation
        // است، فقط قفل‌شدنِ اولیه سریع‌تر می‌شود.
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'آبتین‌مپ در حال دریافت موقعیت است',
          notificationText: 'مسیریابی و ردیابی موقعیت در پس‌زمینه فعال است',
          // اپ نباید هنگام مرور معمول نقشه یا در پس‌زمینه نمایشگر را دائماً
          // روشن نگه دارد. foreground service مسیر موقعیت را حفظ می‌کند، اما
          // wake-lock فقط برای ناوبریِ صریح باید از کنترل اختصاصی استفاده شود.
          enableWakeLock: false,
          notificationIcon: AndroidResource(
            name: 'ic_launcher',
            defType: 'mipmap',
          ),
        ),
      );
    }
    if (Platform.isIOS || Platform.isMacOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        // اجازه می‌دهد استریمِ موقعیت وقتی اپ در پس‌زمینه است هم ادامه پیدا
        // کند — بدونش iOS معمولاً چند ثانیه بعد از پس‌زمینه‌رفتن، آپدیت‌ها
        // را متوقف می‌کند (تنظیمِ متناظرِ ACCESS_BACKGROUND_LOCATION در
        // اندروید).
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );
  }

  void _onAccel(UserAccelerometerEvent e) {
    final mag = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    _accelBaseline += (mag - _accelBaseline) * 0.01;
    final instantJerk = (mag - _accelBaseline).abs();
    _accelJerk += (instantJerk - _accelJerk) * 0.25;
    _accelMotionNoise +=
        (math.min(_accelJerk * _accelJerk, 12.0) - _accelMotionNoise) * 0.18;
  }

  void _onGyroscope(GyroscopeEvent event) {
    final angularRate = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    _gyroAngularRate += (angularRate - _gyroAngularRate) * 0.13;
    final turnEvidence = math.min(_gyroAngularRate * _gyroAngularRate, 8.0);
    _gyroMotionNoise += (turnEvidence - _gyroMotionNoise) * 0.16;
  }

  void _onPosition(Position p, int runId) {
    if (_disposed || runId != _runId) return;
    if (!_isValidCoordinate(p.latitude, p.longitude)) {
      
      return;
    }
    final tsMs = p.timestamp.millisecondsSinceEpoch;
    // برخی دستگاه‌ها هنگام بازگشت از پس‌زمینه یا تغییر provider، همان فیکس را
    // دوباره یا با timestamp قدیمی‌تر می‌فرستند. ورود آن به کالمن/انیماتور
    // می‌تواند یک قطعهٔ رو به عقب و جهش سرعت ایجاد کند.
    if (_lastGpsMeasurementTsMs != null && tsMs <= _lastGpsMeasurementTsMs!) {
      
      return;
    }
    // Reject physically implausible jumps before any Kalman/filter state is
    // updated. A single bad GNSS fix must never become the new reference for
    // the position, speed or heading pipeline. The gate scales with the
    // reported accuracy and elapsed time so genuine highway movement is not
    // clipped while 100m+ teleport-like fixes are ignored.
    final previousLat = _lastAcceptedRawLat;
    final previousLng = _lastAcceptedRawLng;
    final previousTs = _lastAcceptedRawTsMs;
    if (previousLat != null && previousLng != null && previousTs != null) {
      final dtSec = (tsMs - previousTs) / 1000.0;
      if (dtSec > 0 && dtSec <= 15) {
        final displacementM = _calculateDistance(
          previousLat, previousLng, p.latitude, p.longitude,
        );
        final reportedAccuracy =
            p.accuracy.isFinite && p.accuracy > 0 ? p.accuracy : 20.0;
        final previousSpeed = _lastAcceptedRawSpeedMs ?? 0.0;
        final currentSpeed = p.speed.isFinite && p.speed >= 0 ? p.speed : 0.0;
        final speedForGate = math.max(previousSpeed, currentSpeed);
        final physicallyExpected = speedForGate * dtSec;
        final allowedJump = math.min(
          120.0,
          math.max(28.0, physicallyExpected + reportedAccuracy * 1.75 + 12.0),
        );
        if (displacementM > allowedJump) {
          
          return;
        }
      }
    }
    _lastGpsMeasurementTsMs = tsMs;
    _lastAcceptedRawLat = p.latitude;
    _lastAcceptedRawLng = p.longitude;
    _lastAcceptedRawTsMs = tsMs;
    _lastAcceptedRawSpeedMs = p.speed.isFinite && p.speed >= 0 ? p.speed : 0.0;
    _lastGpsFixAt = DateTime.now();
    if (_isPredictingGpsGap) {
      _isPredictingGpsGap = false;
      
    }
    _restartAttempts = 0;
    _noFixWatchdog?.cancel();
    _noFixWatchdog = null;
    if (!_gotFirstFix) {
      _gotFirstFix = true;
      _setState(LocationState.active);
      final ms = _startedAt == null
          ? null
          : DateTime.now().difference(_startedAt!).inMilliseconds;
      
    }
    final posAccuracy =
        p.accuracy.isFinite && p.accuracy > 0 ? p.accuracy : 15.0;

    // GNSS/Doppler تنها منبع اصلی سرعت است. برخی providerهای Fused در
    // شروع/بازگشت، با وجود تغییر مکان واقعی speed=0 می‌فرستند؛ در همان حالت
    // محدود، فاصلهٔ بین دو فیکسِ دقیق جایگزین می‌شود. سنسورهای حرکت به‌دلیل
    // drift برای ساخت سرعت مستقیم استفاده نمی‌شوند و فقط نویز کالمن را تنظیم
    // می‌کنند.
    final speedEstimate = _speedFusion.measure(
      latitude: p.latitude,
      longitude: p.longitude,
      timestampMs: tsMs,
      gnssSpeedMs: p.speed,
      accuracyMeters: posAccuracy,
    );
    final measuredSpeedMs = speedEstimate.metersPerSecond;

    // فیلتر کالمن مشترک همیشه با فیکس خام تغذیه می‌شود (برای اینکه دیاگنوستیک
    // زنده باشد حتی وقتی فعال نیست)، اما فقط وقتی [useJointKalman] روشن است
    // خروجی‌اش جایگزین مسیر فیلتر ۱بعدیِ فعلی می‌شود.
    final rawSample = KalmanLocationSample(
      latitude: p.latitude,
      longitude: p.longitude,
      speedMs: measuredSpeedMs,
      bearingDeg: p.heading.isFinite && p.heading >= 0 ? p.heading : 0.0,
      accuracyMeters: posAccuracy,
      // سرعت فاصله‌ای از سرعت داپلر کم‌اطمینان‌تر است، پس کالمن آن را با
      // نویز بزرگ‌تر می‌پذیرد و نمی‌تواند با یک فیکس، عدد سرعت را بپراند.
      speedAccuracyMs: speedEstimate.source == SpeedSource.gnss &&
              p.speedAccuracy.isFinite &&
              p.speedAccuracy > 0
          ? p.speedAccuracy
          : 4.0,
      timestampMs: tsMs,
    );
    final sensorProcessNoise =
        (_accelMotionNoise + _gyroMotionNoise * 0.65).clamp(0.0, 16.0);
    final jointFiltered = _jointKalman.process(
      rawSample,
      extraProcessNoise: sensorProcessNoise,
    );
    if (!_jointKalmanDiagnosticsController.isClosed) {
      _jointKalmanDiagnosticsController.add(JointKalmanDiagnostics(
        enabled: useJointKalman,
        raw: rawSample,
        filtered: jointFiltered,
        totalJitterReducedMeters: _jointKalman.totalJitterReducedMeters,
        processNoiseQ: _jointKalman.processNoiseQ,
        measurementNoiseMultiplier: _jointKalman.measurementNoiseMultiplier,
      ));
    }

    if (useJointKalman) {
      // پیش‌تر این مسیر هیچ hysteresisی نداشت — یعنی اگر کاربر فیلترِ
      // مشترک را فعال می‌کرد، همان باگِ «رقصِ مکان‌نما حین توقف» که مسیرِ
      // ۱بعدی از قبل حلش کرده بود دوباره برمی‌گشت. حالا هر دو مسیر از
      // همان [_applyStationaryHysteresis] مشترک استفاده می‌کنند.
      // یک speed spike کوتاه نباید به‌تنهایی قفل توقف را باز کند. در عین
      // حال اگر مدل کالمن و سرعت خام هر دو حرکت را تأیید کنند، حرکت واقعی
      // (مثلاً شتاب‌گیری پس از چراغ) بدون تأخیر غیرعادی وارد می‌شود.
      final rawSpeedMs = rawSample.speedMs;
      final jointIsMoving = rawSpeedMs >= 0.8 ||
          (jointFiltered.speedMs > 1.2 && _lastPipelineSpeedKmh > 3.0);
      final locked = _applyStationaryHysteresis(
        lat: jointFiltered.latitude,
        lng: jointFiltered.longitude,
        isMoving: jointIsMoving,
      );
      final speedKmh =
          locked.stationary ? 0.0 : math.max(jointFiltered.speedMs, 0) * 3.6;
      final headingDeg = _smoothedHeading(
        headingDeg: jointFiltered.bearingDeg,
        speedKmh: speedKmh,
        timestampMs: tsMs,
        turningEvidence: _gyroAngularRate,
      );
      _lastPipelineSpeedKmh = speedKmh;
      _controller.add(VehiclePosition(
        lat: locked.lat,
        lng: locked.lng,
        headingDeg: headingDeg,
        speedKmh: speedKmh,
        accuracyM: jointFiltered.accuracyMeters,
      ));
      return;
    }

    // Advanced Filtering: Combine high process noise for movement and low for stops
    final isMoving = measuredSpeedMs >= 0.8;
    final dynamicProcessNoise = isMoving ? 2.5 : 0.2;

    // We update the filter noise dynamically based on movement state
    final filteredLatRaw = _yFilter.process(
        p.latitude, posAccuracy / _metersPerDegLat, tsMs,
        extraProcessNoise: dynamicProcessNoise / _metersPerDegLat);
    final filteredLngRaw = _xFilter.process(p.longitude,
        posAccuracy / (_metersPerDegLat * math.cos(degToRad(p.latitude))), tsMs,
        extraProcessNoise: dynamicProcessNoise /
            (_metersPerDegLat * math.cos(degToRad(p.latitude))));

    // Strict Hysteresis: Prevents micro-movements during stops (Google Maps Style)
    final locked = _applyStationaryHysteresis(
      lat: filteredLatRaw,
      lng: filteredLngRaw,
      isMoving: isMoving,
    );
    final filteredLat = locked.lat;
    final filteredLng = locked.lng;
    final positionStationary = locked.stationary;

    final rawSpeedMs = p.speed.isFinite && p.speed >= 0 ? p.speed : 0.0;
    final speedAccuracy =
        p.speedAccuracy.isFinite && p.speedAccuracy > 0 ? p.speedAccuracy : 1.5;

    final accelExtraNoise = math.min(_accelJerk * 2.5, 6.0);

    final adaptiveNoise = (_accelJerk > 1.5) ? 2.2 : 0.0;

    final filteredSpeedMs = _speedFilter.process(
      rawSpeedMs,
      speedAccuracy,
      tsMs,
      extraProcessNoise: accelExtraNoise + adaptiveNoise,
    );
    // نویزِ فیلدِ speed خودِ GPS (مبتنی‌بر داپلر) کاملاً مستقل از دقتِ
    // موقعیت است — روی خیلی گیرنده‌ها حتی وقتی ماشین کاملاً پارک است این
    // فیلد مقادیرِ چندکیلومتر/ساعتیِ متغیر و نامنظم می‌دهد (دقیقاً همان چیزی
    // که کاربر با سرعت‌سنجِ نوسانی حین توقف گزارش کرد). چون بالاتر با
    // hysteresisِ موقعیت همین لحظه تشخیص دادیم که ماشین واقعاً جابه‌جا
    // نشده، این نویز را نادیده می‌گیریم و سرعتِ نمایشی را صفر می‌کنیم —
    // به‌جای این‌که به خروجیِ فیلترِ کالمنِ سرعت (که وقتی speedAccuracy از
    // OS نامعتبر/بیش‌ازحد خوش‌بینانه گزارش شود، این نویز را کامل رد می‌کند)
    // اعتماد کنیم.
    final speedKmh =
        positionStationary ? 0.0 : math.max(filteredSpeedMs, 0) * 3.6;
    _lastPipelineSpeedKmh = speedKmh;

    final headingDeg = _smoothedHeading(
      headingDeg: p.heading,
      speedKmh: speedKmh,
      timestampMs: tsMs,
    );

    // فیلتر روی درجه‌ی جغرافیایی کار می‌کند، پس عدم‌قطعیتش هم بر حسب درجه
    // است؛ قبلاً همین عدد مستقیماً به‌عنوان «متر» گزارش می‌شد و دایره‌ی دقتِ
    // مکان‌نما عملاً صفر می‌ماند. حالا به متر تبدیل می‌شود.
    final uncertaintyDeg = math.sqrt(
      _xFilter.uncertainty * _xFilter.uncertainty +
          _yFilter.uncertainty * _yFilter.uncertainty,
    );
    final accuracyM = math.max(uncertaintyDeg * _metersPerDegLat, posAccuracy);

    _controller.add(VehiclePosition(
      lat: filteredLat,
      lng: filteredLng,
      headingDeg: headingDeg,
      speedKmh: speedKmh,
      accuracyM: accuracyM,
    ));
  }

  void _predictGpsGap() {
    if (_disposed || !useJointKalman || _lastGpsFixAt == null) return;
    final now = DateTime.now();
    final gap = now.difference(_lastGpsFixAt!);
    if (gap < _gpsGapBeforePrediction || gap > _maxGpsPredictionGap) return;
    final predicted = _jointKalman.predictOnly(now.millisecondsSinceEpoch);
    if (predicted == null || predicted.speedMs < 0.35) return;
    if (!_isPredictingGpsGap) {
      _isPredictingGpsGap = true;
      
    }
    // عدم‌قطعیت با زمان افزایش می‌یابد؛ بنابراین اگر خاموشی ادامه پیدا کند،
    // map matching به‌زور خودرو را روی یک جادهٔ دور snap نمی‌کند.
    final grownAccuracy =
        (predicted.accuracyMeters + gap.inMilliseconds / 1000 * 6)
            .clamp(1.0, 80.0)
            .toDouble();
    _lastPipelineSpeedKmh = predicted.speedMs * 3.6;
    _controller.add(VehiclePosition(
      lat: predicted.latitude,
      lng: predicted.longitude,
      headingDeg: predicted.bearingDeg,
      speedKmh: predicted.speedMs * 3.6,
      accuracyM: grownAccuracy,
      isEstimated: true,
    ));
  }

  void _requestNetworkAssistIfNeeded() {
    if (_disposed ||
        !useJointKalman ||
        !_gotFirstFix ||
        _lastGpsFixAt == null ||
        _networkAssistInFlight) {
      return;
    }
    final now = DateTime.now();
    final gap = now.difference(_lastGpsFixAt!);
    if (gap < _networkAssistAfterGap) return;
    if (_lastNetworkAssistAt != null &&
        now.difference(_lastNetworkAssistAt!) < _networkAssistInterval) {
      return;
    }
    _lastNetworkAssistAt = now;
    _networkAssistInFlight = true;
    unawaited(_fetchNetworkAssist());
  }

  Future<void> _fetchNetworkAssist() async {
    try {
      // LocationAccuracy.medium به سرویس مکان سیستم اجازه می‌دهد از Wi‑Fi و
      // دکل مخابراتی استفاده کند. این درخواست به‌عمد کم‌تکرار است تا هم
      // باتری و هم حریم خصوصی کاربر حفظ شود و وابستگی به API خارجی ندارد.
      final network = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 3),
      );
      if (_disposed || _lastGpsFixAt == null) return;
      final gap = DateTime.now().difference(_lastGpsFixAt!);
      if (gap < _networkAssistAfterGap) return;
      final accuracy = network.accuracy.isFinite && network.accuracy > 0
          ? network.accuracy
          : 250.0;
      // موقعیت شبکه‌ای بسیار دور یا نامعتبر به pipeline وارد نمی‌شود؛ گراف
      // آفلاین نیز تنها در دقت‌های مناسب قادر به snap خواهد بود.
      if (accuracy > 1000 ||
          !network.latitude.isFinite ||
          !network.longitude.isFinite) {
        
        return;
      }
      final fused = _jointKalman.processPositionOnly(
        KalmanLocationSample(
          latitude: network.latitude,
          longitude: network.longitude,
          speedMs: 0,
          bearingDeg: 0,
          accuracyMeters: accuracy,
          speedAccuracyMs: 1e6,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      
      _controller.add(VehiclePosition(
        lat: fused.latitude,
        lng: fused.longitude,
        headingDeg: fused.bearingDeg,
        // Network coordinates must never rewrite the vehicle speed. Wi-Fi/cell
        // fixes have no reliable velocity measurement and used to inject 0 km/h
        // into the same Kalman state, which made braking/speed jump visually.
        speedKmh: _lastPipelineSpeedKmh,
        accuracyM: math.max(fused.accuracyMeters, accuracy),
        isEstimated: true,
      ));
    } catch (_) {
      // در همهٔ گوشی‌ها یا همهٔ تونل‌ها دادهٔ شبکه وجود ندارد. شکست این منبع
      // کمکی نباید به سرویس اصلی GPS یا پیش‌بینی کالمن لطمه بزند.
    } finally {
      _networkAssistInFlight = false;
    }
  }

  double _smoothedHeading({
    required double headingDeg,
    required double speedKmh,
    required int timestampMs,
    double turningEvidence = 0,
  }) {
    if (speedKmh >= _headingFreezeSpeedKmh &&
        headingDeg >= 0 &&
        headingDeg.isFinite) {
      final dtSec = _lastHeadingTsMs == null
          ? 1.0
          : math.max((timestampMs - _lastHeadingTsMs!) / 1000.0, 0.0);
      final baseAlpha = 1 - math.exp(-dtSec / _headingTimeConstantSec);
      final alpha = (baseAlpha + turningEvidence * 0.06).clamp(0.0, 0.72);
      _smoothHeading = _lerpAngle(_smoothHeading, headingDeg, alpha);
      _lastHeadingTsMs = timestampMs;
    } else {
      // هنگام توقف heading GPS/قطب‌نما پایدار نیست. مقدارِ آخرین حرکت را
      // نگه می‌داریم تا پیکان هنگام ایستادن بی‌دلیل نچرخد.
      _smoothHeading ??=
          (headingDeg >= 0 && headingDeg.isFinite) ? headingDeg : 0;
    }
    return _smoothHeading ?? 0;
  }

  bool _isValidCoordinate(double lat, double lng) =>
      lat.isFinite && lng.isFinite && lat.abs() <= 90 && lng.abs() <= 180;

  double _lerpAngle(double? current, double target, double alpha) {
    if (current == null) return target;
    var diff = (target - current + 540) % 360 - 180;
    return (current + diff * alpha + 360) % 360;
  }

  double _calculateDistance(
      double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371000.0;
    final dLat = degToRad(lat2 - lat1);
    final dLng = degToRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(degToRad(lat1)) *
            math.cos(degToRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  /// قفلِ توقف مشترکِ هر دو مسیرِ فیلتر (۱بعدیِ فعلی و کالمنِ مشترک
  /// اختیاری): اگر جابه‌جاییِ فیکسِ تازه‌فیلترشده نسبت به آخرین فیکسِ
  /// ارسال‌شده کمتر از آستانه باشد (۱ متر حین حرکت، ۵ متر حین توقف)،
  /// همان مختصاتِ قبلی را نگه می‌دارد — دقیقاً همان hysteresisِ سبکِ
  /// گوگل‌مپ که قبلاً فقط داخلِ مسیرِ ۱بعدی بود. تنها یک محلِ حقیقتِ
  /// [_lastSentLat]/[_lastSentLng] وجود دارد، پس فعال/غیرفعال‌کردنِ
  /// [useJointKalman] بینِ دو فیکس دیگر باعثِ یک پرشِ ناگهانی نمی‌شود.
  ({double lat, double lng, bool stationary}) _applyStationaryHysteresis({
    required double lat,
    required double lng,
    required bool isMoving,
  }) {
    var outLat = lat;
    var outLng = lng;
    var stationary = false;
    if (_lastSentLat != null && _lastSentLng != null) {
      final distMoved =
          _calculateDistance(lat, lng, _lastSentLat!, _lastSentLng!);
      final moveThreshold = isMoving ? 1.0 : 5.0;
      if (distMoved < moveThreshold) {
        outLat = _lastSentLat!;
        outLng = _lastSentLng!;
        stationary = true;
      }
    }
    _lastSentLat = outLat;
    _lastSentLng = outLng;
    return (lat: outLat, lng: outLng, stationary: stationary);
  }

  /// Cancels active GPS/sensor subscriptions and timers without closing the
  /// broadcast controllers, so [start] can be called again later (e.g. when
  /// Map is reopened) — unlike [dispose], which is a one-way teardown.
  void stop() {
    _disposed = true;
    _runId++;
    _restartTimer?.cancel();
    _noFixWatchdog?.cancel();
    _gpsGapPredictionTimer?.cancel();
    _networkAssistTimer?.cancel();
    _sub?.cancel();
    _sub = null;
    _accelSub?.cancel();
    _accelSub = null;
    _gyroSub?.cancel();
    _gyroSub = null;
    _restartAttempts = 0;
    _useRawLocationManager = false;
    _setState(LocationState.waiting);
  }

  void dispose() {
    _disposed = true;
    _runId++;
    _restartTimer?.cancel();
    _noFixWatchdog?.cancel();
    _gpsGapPredictionTimer?.cancel();
    _networkAssistTimer?.cancel();
    _sub?.cancel();
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _controller.close();
    _jointKalmanDiagnosticsController.close();
    _stateController.close();
  }
}

double degToRad(double deg) => deg * math.pi / 180;
