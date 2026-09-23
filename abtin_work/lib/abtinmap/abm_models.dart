import 'dart:math' as math;

/// کلاس‌های جاده — جدول ROAD_CLASSES در abtinmap_build.py
class AbmKlass {
  static const motorway = 1;
  static const trunk = 2;
  static const primary = 3;
  static const secondary = 4;
  static const tertiary = 5;
  static const residential = 6;
  static const service = 7;
  static const unclassified = 8;
  static const track = 9;
  static const footway = 10;
  static const cycleway = 11;
  static const steps = 12;

  static const railway = 20;
  static const waterArea = 30;
  static const waterway = 31;
  static const green = 32;
  static const urban = 33;
  static const building = 34;
  static const boundary = 40;

  // POI (جدول POI_CLASSES)
  static const poiFuel = 50;
  static const poiParking = 51;
  static const poiHospital = 52;
  static const poiPharmacy = 53;
  static const poiPolice = 54;
  static const poiSchool = 55;
  static const poiRestaurant = 56;
  static const poiCafe = 57;
  static const poiBank = 58;
  static const poiHotel = 59;
  static const poiSupermarket = 60;
  static const poiMosque = 61;
  static const poiToilets = 62;
  static const poiBusStation = 63;
  static const poiAirport = 64;
  static const poiAttraction = 65;
  static const poiPark = 66;
  static const poiPitch = 67;
  static const poiPlace = 68;

  /// دوربین/تابلوی کنترل سرعت.
  static const poiSpeedCamera = 70;

  /// سرعت‌گیر فیزیکی (طوقه/دست‌انداز — تگ traffic_calming در OSM).
  static const poiSpeedBump = 71;

  static const poiTrafficLight = 72;

  /// همه‌ی کلاس‌های POI قابل‌نمایش روی نقشه (سرعت‌گیر/دوربین جزو فیلترِ
  /// کاربر نیست — ایمنی‌اند و همیشه نمایش داده می‌شوند).
  static const List<int> selectablePoiKlasses = [
    poiFuel,
    poiParking,
    poiHospital,
    poiPharmacy,
    poiPolice,
    poiSchool,
    poiRestaurant,
    poiCafe,
    poiBank,
    poiHotel,
    poiSupermarket,
    poiMosque,
    poiToilets,
    poiBusStation,
    poiAirport,
    poiAttraction,
    poiPark,
    poiPitch,
    poiPlace,
    poiSpeedCamera,
    poiSpeedBump,
    poiTrafficLight,
  ];

  static bool isRoad(int klass) => klass >= 1 && klass <= 12;

  /// کلاس‌هایی که *اصولاً* قابل عبور با خودرو هستند (بزرگراه..جادهٔ خاکی).
  /// پیاده‌رو/دوچرخه‌رو/پله (۱۰..۱۲) هرگز خودرو را از خود عبور نمی‌دهند.
  static bool isDrivable(int klass) => klass >= 1 && klass <= 9;
}

/// تخمین عرض قابل‌کاربرد جاده بر اساس کلاس آن.
///
/// ⚠️ فایل .abm فعلاً هیچ فیلد عرضِ متریِ واقعی (نقشه‌برداری‌شده) ندارد —
/// این اعداد صرفاً یک *تخمینِ* معقول بر مبنای کلاس OSM هستند (میانگین عرض
/// معمول هر نوع راه)، نه اندازه‌ی دقیق آن جادهٔ به‌خصوص. وقتی فایل ساخت
/// نقشه (abtinmap_build.py) عرض واقعی را در فرمت ذخیره کند، این جدول باید
/// با آن مقدار دقیق جایگزین شود.
class AbmWidthEstimate {
  static const Map<int, double> _byKlass = {
    AbmKlass.motorway: 15.0,
    AbmKlass.trunk: 12.0,
    AbmKlass.primary: 9.0,
    AbmKlass.secondary: 7.5,
    AbmKlass.tertiary: 6.5,
    AbmKlass.residential: 6.0,
    AbmKlass.unclassified: 5.0,
    AbmKlass.service: 3.5,
    AbmKlass.track: 2.5,
  };

  /// عرض تخمینی به متر برای [klass]؛ برای کلاس‌های غیرجاده‌ای یا ناشناس
  /// یک مقدار محافظه‌کارانه‌ی کوچک (۲ متر) برمی‌گرداند.
  static double metersFor(int klass, {bool surfaceUnpaved = false}) {
    final base = _byKlass[klass] ?? 2.0;
    // جادهٔ خاکی/شنی معمولاً به دلیل فرسایش و نبود جدول‌بندی، عملاً از
    // عرض اسمی‌اش باریک‌تر رانده می‌شود.
    return surfaceUnpaved ? base * 0.8 : base;
  }
}

/// بیت‌های فیلد attr (پاس ۲ در abtinmap_build.py).
class AbmAttr {
  static const onewayForward = 1 << 0; // حرکت در جهت رو به جلو ممنوع
  static const onewayBackward = 1 << 1; // حرکت در جهت معکوس ممنوع
  static const bridge = 1 << 2;
  static const tunnel = 1 << 3;
  static const roundabout = 1 << 4;
  static const link = 1 << 5;
  static const toll = 1 << 6;
  static const surfaceUnpaved = 1 << 7;
  static const reversed = 1 << 8;
  static const noAccess = 1 << 9;
  static const junctionNamed = 1 << 10;
  static const explicitMaxspeed = 1 << 11;
}

/// نقطه‌ی جغرافیایی سبک (وابسته به هیچ پکیج نقشه‌ای نیست).
class AbmPoint {
  const AbmPoint(this.lon, this.lat);
  final double lon;
  final double lat;

  @override
  String toString() => '($lon, $lat)';
}

class AbmWay {
  AbmWay({
    required this.klass,
    required this.attr,
    required this.minZoom,
    required this.name,
    required this.speedCode,
    required this.refs,
    this.widthDm = 0,
  });

  final int klass;
  final int attr;
  final int minZoom;
  final String name;
  final int speedCode;

  /// عرض واقعیِ راه به دسی‌متر (۱ = ۰.۱ متر)، از فایل .abm نسخه‌ی ≥۲ خوانده
  /// می‌شود (خودِ فایل ساخت نقشه آن را از تگ‌های width/lanes یا مقدار
  /// پیش‌فرضِ کلاس محاسبه کرده). صفر یعنی فایل نسخه‌ی قدیمی‌تر است و عرض
  /// واقعی موجود نیست — در این حالت [estimatedWidthMeters] به تخمینِ کلاس
  /// برمی‌گردد.
  final int widthDm;

  /// اندیس گره‌ها در بخش nodes همان کاشی.
  final List<int> refs;

  bool get isRoundabout => (attr & AbmAttr.roundabout) != 0;
  bool get isLink => (attr & AbmAttr.link) != 0;
  bool get isTunnel => (attr & AbmAttr.tunnel) != 0;
  bool get isBridge => (attr & AbmAttr.bridge) != 0;
  bool get hasExplicitMaxspeed => (attr & AbmAttr.explicitMaxspeed) != 0;

  /// جهت مجاز حرکت — این بیت‌ها فقط برای نمایش/دیباگ‌اند؛ منبع واقعی هزینه‌ی
  /// جهت‌دار همان forward10/backward10 روی AbmEdge است که گراف مسیریابی از
  /// آن‌ها استفاده می‌کند (در موتور قدیمی).
  bool get isOnewayForward => (attr & AbmAttr.onewayForward) != 0;
  bool get isOnewayBackward => (attr & AbmAttr.onewayBackward) != 0;

  /// جاده‌ی بسته/بدون دسترسی عمومی (private، construction، و مشابه) —
  /// این way نباید وارد گراف مسیریابی شود حتی اگر یال‌هایش هزینه‌ی مثبت دارند.
  bool get isNoAccess => (attr & AbmAttr.noAccess) != 0;

  bool get isToll => (attr & AbmAttr.toll) != 0;

  bool get isSurfaceUnpaved => (attr & AbmAttr.surfaceUnpaved) != 0;

  /// آیا این کلاس جاده اصولاً برای خودرو قابل عبور است؟ (نه پیاده‌رو/دوچرخه/پله)
  bool get isCarPassableClass => AbmKlass.isDrivable(klass);

  /// آیا عرض این راه از داده‌ی واقعیِ نقشه (نه تخمینِ کلاس) می‌آید؟
  bool get hasRealWidth => widthDm > 0;

  /// عرض راه به متر — اگر فایل عرض واقعی داشته باشد ([hasRealWidth]) همان
  /// برگردانده می‌شود، وگرنه یک *تخمین* بر اساس کلاس راه (نگاه کنید به
  /// [AbmWidthEstimate]).
  double get estimatedWidthMeters => hasRealWidth
      ? widthDm / 10.0
      : AbmWidthEstimate.metersFor(klass, surfaceUnpaved: isSurfaceUnpaved);

  /// راهی که آن‌قدر باریک است که عبور خودروی معمولی از آن (به‌خصوص با
  /// ماشین بزرگ/شلوغی) دشوار یا مشکوک است. اگر [hasRealWidth] باشد این
  /// یک واقعیتِ اندازه‌گیری‌شده است، وگرنه صرفاً هشدارِ مبتنی بر تخمینِ کلاس.
  bool get isNarrowForCar => estimatedWidthMeters < 3.0;

  /// محدودیت سرعت به km/h — جدول ۵ فرمت (encode_maxspeed).
  /// null یعنی نامشخص/بی‌محدودیت.
  int? get speedLimitKmh {
    if (speedCode >= 1 && speedCode <= 40) return speedCode * 5;
    if (speedCode == 200) return 50; // پیش‌فرض شهری ایران
    if (speedCode == 201) {
      switch (klass) {
        case AbmKlass.motorway:
          return 120;
        case AbmKlass.trunk:
          return 100;
        case AbmKlass.primary:
          return 90;
        case AbmKlass.secondary:
          return 80;
        default:
          return 70;
      }
    }
    return null; // 0 = نامشخص، 255 = بی‌محدودیت
  }
}

/// یال گراف مسیریابی: از `refs[a]` تا `refs[b]` روی way با اندیس [wayIndex].
/// هزینه‌ها بر حسب دهم‌ثانیه ذخیره شده‌اند (travel-time بر پایه speed_kmh).
class AbmEdge {
  const AbmEdge(this.wayIndex, this.a, this.b, this.forward10, this.backward10);
  final int wayIndex;
  final int a;
  final int b;
  final int forward10;
  final int backward10;

  double get forwardSeconds => forward10 / 10.0;
  double get backwardSeconds => backward10 / 10.0;
}

class AbmArea {
  AbmArea({
    required this.klass,
    required this.attr,
    required this.minZoom,
    required this.name,
    required this.rings,
  });

  final int klass;
  final int attr;
  final int minZoom;
  final String name;
  final List<List<AbmPoint>> rings;

  double get buildingHeightMeters =>
      klass == AbmKlass.building ? (attr > 0 ? attr / 10.0 : 5.0) : 0.0;
}

class AbmPoi {
  AbmPoi({
    required this.point,
    required this.klass,
    required this.minZoom,
    required this.name,
  });

  final AbmPoint point;
  final int klass;
  final int minZoom;
  final String name;

  bool get isSpeedCamera => klass == AbmKlass.poiSpeedCamera;

  bool get isSpeedBump => klass == AbmKlass.poiSpeedBump;

  /// ایستگاه/مرکز پلیس (amenity=police در OSM).
  bool get isPoliceStation => klass == AbmKlass.poiPolice;

  /// چراغ راهنمایی (highway=traffic_signals در OSM).
  bool get isTrafficLight => klass == AbmKlass.poiTrafficLight;

  /// دوربین یا سرعت‌گیر — هر چیزی که در حین رانندگی باید هشدار داده شود.
  bool get isSpeedAlert => isSpeedCamera || isSpeedBump;

  /// همه‌ی POIهایی که باید در نوارِ هشدار حین ناوبری نمایش داده شوند
  /// (دوربین/سرعت‌گیر + ایستگاه پلیس + چراغ راهنمایی نزدیکِ مسیر).
  bool get isNavigationAlert =>
      isSpeedAlert || isPoliceStation || isTrafficLight;
}

/// یک کاشی رمزگشایی‌شده (هندسه + گراف + POI).
class AbmTile {
  AbmTile({
    required this.z,
    required this.x,
    required this.y,
    required this.origin,
  });

  final int z;
  final int x;
  final int y;
  final AbmPoint origin;

  final List<AbmPoint> nodes = [];
  final List<AbmWay> ways = [];
  final List<AbmEdge> edges = [];
  final List<AbmArea> areas = [];
  final List<AbmPoi> pois = [];

  /// اندیس گره‌های مرزی → کلید جهانی گره (برای دوخت گراف بین کاشی‌ها).
  final Map<int, int> border = {};

  AbmPoint nodeAt(int i) => nodes[i];
}

/// تبدیل‌های Web-Mercator — هم‌ارز `tile_xy` / `tile_origin` در خواننده‌ی مرجع.
class AbmTileMath {
  static const double maxLat = 85.05112878;

  static int tileX(double lon, int z) {
    final n = 1 << z;
    final x = ((lon + 180.0) / 360.0 * n).floor();
    return x.clamp(0, n - 1);
  }

  static int tileY(double lat, int z) {
    final n = 1 << z;
    final clamped = lat.clamp(-maxLat, maxLat);
    final r = clamped * math.pi / 180.0;
    final y =
        ((1.0 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2.0 * n)
            .floor();
    return y.clamp(0, n - 1);
  }

  static AbmPoint tileOrigin(int x, int y, int z) {
    final n = 1 << z;
    final lon = x / n * 360.0 - 180.0;
    final lat = _atanSinh(math.pi * (1 - 2 * y / n)) * 180.0 / math.pi;
    return AbmPoint(lon, lat);
  }

  static double _atanSinh(double v) {
    final sinh = (math.exp(v) - math.exp(-v)) / 2;
    return math.atan(sinh);
  }

  static int tileId(int z, int x, int y) => (z << 44) | (x << 22) | y;

  /// کلید جهانی گره — هم‌ارز `gkey` در خواننده‌ی مرجع.
  static int graphKey(int lonE7, int latE7) =>
      (latE7 + 900000000) * 3600000001 + (lonE7 + 1800000000);

  static double haversineMeters(AbmPoint a, AbmPoint b) {
    const r = 6371000.0;
    final dLat = (b.lat - a.lat) * math.pi / 180;
    final dLon = (b.lon - a.lon) * math.pi / 180;
    final la1 = a.lat * math.pi / 180;
    final la2 = b.lat * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(la1) * math.cos(la2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  static double bearing(AbmPoint from, AbmPoint to) {
    final lat1 = from.lat * math.pi / 180;
    final lat2 = to.lat * math.pi / 180;
    final dLon = (to.lon - from.lon) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }
}
