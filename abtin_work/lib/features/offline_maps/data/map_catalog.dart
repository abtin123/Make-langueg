import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:abtin_maps/core/geo/geo_types.dart';
import 'package:path_provider/path_provider.dart';

import '../../../abtinmap/abm_map_service.dart';
import 'iran_provinces.dart' show Province;

/// اطلاعات منبع داده‌ای که همراه هر بستهٔ نقشه منتشر می‌شود.
///
/// این metadata بخشی از manifest انتشار است؛ renderer به آن وابسته نیست اما
/// UI همیشه می‌تواند انتساب و مسیر license را، حتی برای فایل نصب‌شدهٔ قدیمی،
/// در اختیار کاربر بگذارد.
class MapDataSource {
  const MapDataSource({
    this.provider = 'Geofabrik / OpenStreetMap',
    this.url = '',
    this.attribution = 'Map data from OpenStreetMap, ODbL 1.0',
    this.licenseUrl = 'https://opendatacommons.org/licenses/odbl/1.0/',
    this.copyrightUrl = 'https://www.openstreetmap.org/copyright',
  });

  static const MapDataSource osm = MapDataSource();

  final String provider;
  final String url;
  final String attribution;
  final String licenseUrl;
  final String copyrightUrl;

  factory MapDataSource.fromJson(Map<String, dynamic> json) => MapDataSource(
        provider: (json['provider'] as String?) ?? osm.provider,
        url: (json['url'] as String?) ?? '',
        attribution: (json['attribution'] as String?) ?? osm.attribution,
        licenseUrl: (json['license_url'] as String?) ?? osm.licenseUrl,
        copyrightUrl: (json['copyright_url'] as String?) ?? osm.copyrightUrl,
      );
}

/// metadata بستهٔ Vector ABM جدید؛ Style و Renderer داخل اپ هستند و ABM فقط داده نگه می‌دارد.
/// این کلاس فقط سازگاری manifest را نگه می‌دارد و دادهٔ style جزو ABM محسوب نمی‌شود.
class VectorMapPackage {
  const VectorMapPackage({
    required this.dayStylePath,
    required this.nightStylePath,
    this.resources = const <String>[],
    this.embedded = true,
  });

  final String dayStylePath;
  final String nightStylePath;
  final List<String> resources;
  final bool embedded;

  List<String> get entryPaths => <String>[
        dayStylePath,
        nightStylePath,
        ...resources,
      ];

  bool get isUsable {
    final paths = entryPaths;
    return embedded &&
        _isSafeRelativePath(dayStylePath) &&
        dayStylePath.toLowerCase().endsWith('.json') &&
        _isSafeRelativePath(nightStylePath) &&
        nightStylePath.toLowerCase().endsWith('.json') &&
        resources.every(_isSafeRelativePath) &&
        paths.toSet().length == paths.length;
  }

  static bool _isSafeRelativePath(String value) {
    final normalized = value.replaceAll('\\', '/');
    return value.trim().isNotEmpty &&
        !normalized.startsWith('/') &&
        !normalized.contains('../') &&
        !normalized
            .split('/')
            .any((segment) => segment.isEmpty || segment == '.');
  }

  factory VectorMapPackage.fromJson(Map<String, dynamic> json) {
    String path(String key) {
      final value = json[key];
      if (value is String) return value;
      if (value is Map<String, dynamic> && value['path'] is String) {
        return value['path'] as String;
      }
      throw FormatException('فیلد vector_map.$key در manifest معتبر نیست.');
    }

    final rawResources = json['resources'];
    return VectorMapPackage(
      embedded: json['embedded'] == true,
      dayStylePath: path('day_style'),
      nightStylePath: path('night_style'),
      resources: rawResources is List
          ? rawResources.whereType<String>().toList(growable: false)
          : const <String>[],
    );
  }
}

/// یک بستهٔ نقشهٔ قابل دانلود (در سطح کشور).
///
/// هر ردیف در صفحهٔ «دانلود نقشه» یک [MapRegion] است و به‌صورت مستقل
/// دانلود، به‌روزرسانی و حذف می‌شود.
///
/// نقشه‌های بزرگ (حجم بیش از سقف ۲ گیگابایتیِ آبجکت‌های ریلیز گیت‌هاب) در
/// مانیفست به چند فایل `files` تقسیم شده‌اند (`XX.abm.part0`, `XX.abm.part1`,
/// ...)؛ [files] همهٔ این پارت‌ها را به ترتیب نگه می‌دارد.
class MapRegion {
  const MapRegion({
    required this.id,
    required this.name,
    required this.nameEn,
    required this.bounds,
    required this.version,
    this.countryCode = '',
    this.countryName = '',
    this.countryNameEn = '',
    this.regionName = '',
    this.regionNameEn = '',
    this.groupOrder = 0,
    this.files = const [],
    this.patch,
    this.totalSizeBytes = 0,
    this.downloadBase = '',
    this.bundledAsset = '',
    this.areaFactor = 1,
    this.source = MapDataSource.osm,
    this.vectorMap,
  });

  /// شناسهٔ یکتا و پایدار بسته (کد دوحرفیِ کشور، مثل «IR» یا «CA»)؛ نام فایل
  /// نصب‌شده هم از همین ساخته می‌شود.
  final String id;

  /// نام فارسی کشور (نمایش در فهرست).
  final String name;

  /// نام انگلیسی؛ برای جست‌وجو و مرتب‌سازی.
  final String nameEn;

  /// کشور مادرِ بسته؛ برای نقشهٔ عادی برابر شناسهٔ خود بسته است و برای
  /// بسته‌های بزرگ مانند US-NE برابر US می‌ماند تا پرچم و سربرگ یکی باشد.
  final String countryCode;
  final String countryName;
  final String countryNameEn;

  /// عنوان ناحیهٔ قابل دانلود در کشورهای تقسیم‌شده، مانند «شمال شرق».
  final String regionName;
  final String regionNameEn;
  final int groupOrder;

  bool get isRegionalPackage => id.toUpperCase() != effectiveCountryCode;
  String get effectiveCountryCode => countryCode.isNotEmpty
      ? countryCode.toUpperCase()
      : id.substring(0, 2).toUpperCase();
  String displayCountryName(bool isEnglish) =>
      isEnglish && countryNameEn.isNotEmpty
          ? countryNameEn
          : countryName.isNotEmpty
              ? countryName
              : isEnglish
                  ? nameEn
                  : name;
  String displayRegionName(bool isEnglish) =>
      isEnglish && regionNameEn.isNotEmpty
          ? regionNameEn
          : regionName.isNotEmpty
              ? regionName
              : isEnglish
                  ? nameEn
                  : name;

  final LatLngBounds bounds;

  /// اثر انگشتِ نسخهٔ منتشرشده (sha256 فایل کامل)؛ مبنای تشخیص «به‌روزرسانی
  /// موجود است». ممکن است خالی باشد (مثلاً برای فهرست پیش‌فرض همراه اپ).
  final String version;

  /// فایل‌های تشکیل‌دهندهٔ این نقشه، به ترتیب اتصال. برای بیشتر کشورها یک
  /// فایل است؛ برای کشورهای بزرگ چند پارت متوالی.
  final List<AbmFilePart> files;

  /// patch اختیاری برای انتقال از یک نسخهٔ مشخصِ محلی به نسخهٔ فعلی؛ فقط در
  /// صورتی استفاده می‌شود که هش فایلِ نصب‌شده با [AbmMapPatch.baseSha256]
  /// برابر باشد.
  final AbmMapPatch? patch;

  final int totalSizeBytes;

  /// پیشوندِ آدرس دانلود (شامل اسلش پایانی). اگر خالی باشد از آدرس پیش‌فرض
  /// ریلیز استفاده می‌شود.
  final String downloadBase;

  /// فقط برای بستهٔ کوچک آزمون همراه APK. نقشه‌های کشورها همچنان از catalog
  /// و release دانلود می‌شوند.
  final String bundledAsset;
  bool get isBundledAsset => bundledAsset.isNotEmpty;

  final double areaFactor;

  /// منبع داده و attribution اجباریِ بستهٔ منتشرشده.
  final MapDataSource source;

  /// metadata نمایش برداریِ داخلی همان archive `CC.abm`. نبود آن یعنی
  /// بستهٔ قدیمی فقط graph مسیریابی دارد و نقشهٔ آفلاین کامل محسوب نمی‌شود.
  final VectorMapPackage? vectorMap;

  /// نمایش سازگار با سرویس‌های موجود که با [Province] کار می‌کنند.
  Province get asProvince => Province(
        id: id,
        name: name,
        bounds: bounds,
        areaFactor: areaFactor,
      );

  /// نام فایل نقشهٔ آفلاینِ نهایی (فرمت .abm) که روی نقشهٔ اصلی رندر می‌شود.
  /// این همان فایلی است که پس از دانلود و (در صورت چندپارتی‌بودن) چسباندنِ
  /// همهٔ پارت‌ها ساخته می‌شود؛ کاشی‌های MapLibre دیگر در رندر زنده استفاده
  /// نمی‌شوند.
  String get abmFileName => '$id.abm';

  /// آیا این نقشه از چند پارت جداگانه تشکیل شده؟
  bool get isMultiPart => files.length > 1;

  /// کل کشور فقط با یک فایل ABM دانلود می‌شود.
  double get totalSizeMb => totalSizeBytes / (1024 * 1024);

  /// حجم تقریبی برای نمایش در رابط کاربری (نام قدیمی، برای سازگاری).
  double get graphSizeMb => totalSizeMb;

  /// فهرست پارت‌های واقعاً قابل‌دانلود؛ اگر مانیفست چیزی نداده باشد (فهرست
  /// پیش‌فرض آفلاین)، یک پارت فرضی معادل خودِ `abmFileName` می‌سازد.
  List<AbmFilePart> get effectiveFiles => files.isNotEmpty
      ? files
      : [AbmFilePart(name: abmFileName, size: totalSizeBytes, sha256: version)];

  String get effectiveDownloadBase =>
      downloadBase.isNotEmpty ? downloadBase : '$kAbmReleaseBase/';

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.contains(query.trim()) ||
        nameEn.toLowerCase().contains(q) ||
        countryName.contains(query.trim()) ||
        countryNameEn.toLowerCase().contains(q) ||
        regionName.contains(query.trim()) ||
        regionNameEn.toLowerCase().contains(q) ||
        id.toLowerCase().contains(q);
  }

  /// ترتیب bbox در مانیفست: [minLon, minLat, maxLon, maxLat] (استاندارد GeoJSON).
  static LatLngBounds _boundsFromBbox(List<dynamic> raw) {
    final v = raw.map((e) => (e as num).toDouble()).toList();
    return LatLngBounds(
      southwest: LatLng(v[1], v[0]),
      northeast: LatLng(v[3], v[2]),
    );
  }

  factory MapRegion.fromJson(Map<String, dynamic> json,
      {String defaultDownloadBase = ''}) {
    final filesJson = (json['files'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AbmFilePart.fromJson)
        .toList();
    final rawPatch = json['patch'];
    final rawSource = json['source'];
    final rawVectorMap = json['vector_map'];
    final code = json['code'] as String;
    return MapRegion(
      id: code,
      name: (json['name_fa'] ?? code) as String,
      nameEn: (json['name_en'] ?? code) as String,
      countryCode: (json['country_code'] as String?) ?? code.substring(0, 2),
      countryName: (json['country_name_fa'] as String?) ??
          (json['name_fa'] ?? code) as String,
      countryNameEn: (json['country_name_en'] as String?) ??
          (json['name_en'] ?? code) as String,
      regionName: (json['region_name_fa'] as String?) ??
          (json['name_fa'] ?? code) as String,
      regionNameEn: (json['region_name_en'] as String?) ??
          (json['name_en'] ?? code) as String,
      groupOrder: (json['group_order'] as num?)?.toInt() ?? 0,
      bounds: _boundsFromBbox(json['bbox'] as List<dynamic>),
      version: (json['sha256'] ?? '') as String,
      files: filesJson,
      patch: rawPatch is Map<String, dynamic>
          ? AbmMapPatch.fromJson(rawPatch)
          : null,
      totalSizeBytes: (json['total_size'] as num?)?.toInt() ?? 0,
      downloadBase: (json['download_base'] as String?) ?? defaultDownloadBase,
      source: rawSource is Map<String, dynamic>
          ? MapDataSource.fromJson(rawSource)
          : MapDataSource.osm,
      vectorMap: rawVectorMap is Map<String, dynamic>
          ? VectorMapPackage.fromJson(rawVectorMap)
          : null,
    );
  }

  /// نمایشِ حداقلیِ یک فایل `.abm` که واقعاً روی دستگاه نصب است ولی هیچ
  /// ردیفی برایش در مانیفست آنلاین پیدا نشد (مثلاً مانیفست در دسترس نیست،
  /// یا نقشه بعداً از فهرست انتشار حذف شده). این‌طور نقشه‌ای باید همچنان
  /// در تب «دانلودشده‌ها» قابل دیدن/فعال‌سازی/حذف باشد؛ فقط اطلاعات نمایشیِ
  /// غنی (پرچم دقیق، حجم رسمی و...) را از مانیفست نمی‌گیرد و به‌جایش مقادیر
  /// واقعیِ فایل روی دیسک (حجم) یا مقادیر خنثی جایگزین می‌شود.
  factory MapRegion.fromInstalledFileOnly({
    required String id,
    required int fileSizeBytes,
  }) {
    final code = id.toUpperCase();
    return MapRegion(
      id: code,
      name: code,
      nameEn: code,
      countryCode: code.length >= 2 ? code.substring(0, 2) : code,
      totalSizeBytes: fileSizeBytes,
      version: '',
      bounds: const LatLngBounds(
        southwest: LatLng(-90, -180),
        northeast: LatLng(90, 180),
      ),
    );
  }
}

LatLngBounds _b(double swLat, double swLng, double neLat, double neLng) =>
    LatLngBounds(
      southwest: LatLng(swLat, swLng),
      northeast: LatLng(neLat, neLng),
    );

/// نتیجهٔ خواندن مانیفست ریلیز.
class MapCatalog {
  const MapCatalog({
    required this.regions,
    required this.fromNetwork,
    this.updatedAt,
  });

  final List<MapRegion> regions;

  /// آیا این فهرست همین حالا از اینترنت گرفته شد؟ (در مقابل کش/پیش‌فرض)
  final bool fromNetwork;
  final DateTime? updatedAt;

  MapRegion? byId(String id) {
    for (final region in regions) {
      if (region.id == id) return region;
    }
    return null;
  }
}

/// خواندن فهرست کشورها از فایل `manifest.json` منتشرشده در ریلیز گیت‌هاب،
/// با کش روی حافظهٔ دستگاه تا اپ در حالت آفلاین هم فهرست را نشان دهد.
class MapCatalogService {
  MapCatalogService({String? manifestUrl, http.Client? client})
      : _manifestUrl = manifestUrl ?? defaultManifestUrl,
        _client = client ?? http.Client();

  static const String defaultManifestUrl = String.fromEnvironment(
    'ABTIN_MAP_MANIFEST_URL',
    defaultValue: kAbmManifestUrl,
  );

  final String _manifestUrl;
  final http.Client _client;
  MapCatalog? _memory;
  DateTime? _memoryLoadedAt;

  Future<File> _cacheFile() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/map_catalog');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File('${dir.path}/manifest.json');
  }

  MapCatalog _parse(String body, {required bool fromNetwork}) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('ساختار مانیفست نامعتبر است.');
    }
    // release اصلی فعلی maps-v4 است. اگر یک manifest قدیمی/ناقص release_tag
    // نداشت، نباید کاربر را به maps-v2 (که دیگر asset نهایی ندارد) بفرستیم.
    final releaseTag = (decoded['release_tag'] as String?) ?? 'maps-v4';
    final defaultBase = kAbmReleaseBase.endsWith('/$releaseTag')
        ? '$kAbmReleaseBase/'
        : 'https://github.com/abtin123/abtin-maps/releases/download/$releaseTag/';
    final rawCountries = decoded['countries'];
    final items = <Map<String, dynamic>>[];
    if (rawCountries is List) {
      for (final item in rawCountries) {
        if (item is Map) {
          items.add(Map<String, dynamic>.from(item));
        }
      }
    } else if (rawCountries is Map) {
      // Also accept manifests whose country entries are keyed by country code.
      for (final entry in rawCountries.entries) {
        if (entry.value is Map) {
          final item = Map<String, dynamic>.from(entry.value as Map);
          item.putIfAbsent('code', () => entry.key.toString());
          items.add(item);
        }
      }
    } else {
      throw const FormatException('فیلد countries در مانیفست معتبر نیست.');
    }
    // The manifest is the single source of truth. Do not filter entries by
    // app language, enabled flags, or a bundled country list.
    final regions = <MapRegion>[];
    for (final item in items) {
      regions.add(MapRegion.fromJson(item, defaultDownloadBase: defaultBase));
    }
    final generatedAt = decoded['generated_at'];
    return MapCatalog(
      regions: regions,
      fromNetwork: fromNetwork,
      updatedAt: generatedAt is String ? DateTime.tryParse(generatedAt) : null,
    );
  }

  /// حداکثر «تازگیِ» کشِ محلیِ مانیفست. تا وقتی کش از این مدت قدیمی‌تر
  /// نشده، اصلاً به شبکه سر زده نمی‌شود — چون مانیفست کشورها به‌ندرت تغییر
  /// می‌کند و چک کردنش با هر بار باز کردن صفحه (چه برسد به هر بار خروج و
  /// ورود به آن) هم غیرضروری است و هم روی اتصال‌های کند/فیلترشده (رایج برای
  /// گیت‌هاب در ایران) کاربر را معطل می‌کند.
  // ساخت‌های زمان‌بندی‌شدهٔ نقشه هفتگی هستند. یک روز، تعادل مناسبی میان
  // آگاهی سریع از نسخهٔ تازه و جلوگیری از تماس شبکه‌ای غیرضروری در هر ورود
  // به صفحه برقرار می‌کند؛ دکمهٔ «بررسی به‌روزرسانی» همچنان فوراً cache را
  // نادیده می‌گیرد.
  // maps-v4 is mutable. Keep the UI responsive with a short in-memory cache,
  // but never keep a release manifest stale for a whole day.
  static const Duration _maxMemoryAge = Duration(minutes: 5);
  static const Duration _maxCacheAge = Duration(minutes: 15);

  /// فهرست بسته‌ها فقط از مانیفست منتشرشده می‌آید. کش صرفاً آخرین نسخهٔ
  /// همان مانیفست است و هیچ فهرست ثابت یا وابسته به زبان وجود ندارد.
  Future<MapCatalog> load({bool forceRefresh = false}) async {
    if (!forceRefresh && _memory != null && _memoryLoadedAt != null &&
        DateTime.now().difference(_memoryLoadedAt!) < _maxMemoryAge) {
      return _memory!;
    }

    final cache = await _cacheFile();

    // مسیر سریع: کش محلی هنوز تازه است — بدون هیچ تماس شبکه‌ای همان
    // برگردانده می‌شود. دکمه‌ی «تازه‌سازی» دستی (forceRefresh) از این مسیر
    // رد می‌شود.
    if (!forceRefresh) {
      try {
        if (cache.existsSync()) {
          final age = DateTime.now().difference(await cache.lastModified());
          if (age < _maxCacheAge) {
            final cached = await cache.readAsString(encoding: utf8);
            final catalog = _parse(cached, fromNetwork: false);
            _memory = catalog;
            _memoryLoadedAt = DateTime.now();
            return catalog;
          }
        }
      } catch (_) {
        // کش خراب یا غیرقابل خواندن است؛ به مسیر شبکه ادامه می‌دهیم.
      }
    }

    try {
      var manifestUri = Uri.parse(_manifestUrl);
      // Force-refresh must not be satisfied by an intermediary cache.
      if (forceRefresh) {
        manifestUri = manifestUri.replace(queryParameters: {
          ...manifestUri.queryParameters,
          '_ts': DateTime.now().millisecondsSinceEpoch.toString(),
        });
      }
      final response = await _client
          .get(manifestUri)
          .timeout(const Duration(seconds: 20));
      // response.body تشخیص charset خودکارِ پکیج http را استفاده می‌کند که
      // بدون هدر charset=utf-8 صریح از سرور، به ISO-8859-1 برمی‌گردد و
      // متن فارسی (مثل name_fa) را خراب می‌کند. اینجا صراحتاً UTF-8 دیکد
      // می‌شود تا مستقل از هدرهای سرور همیشه درست باشد.
      final bodyUtf8 = utf8.decode(response.bodyBytes);
      if (response.statusCode == 200 && bodyUtf8.length > 2) {
        final catalog = _parse(bodyUtf8, fromNetwork: true);
        await cache.writeAsString(bodyUtf8, flush: true, encoding: utf8);
        _memory = catalog;
        _memoryLoadedAt = DateTime.now();
        return catalog;
      }
      // A 404 from the fixed maps-v4 release means the manifest was removed
      // or the release is not published. Do NOT resurrect the deleted catalog
      // from a stale local cache; that is exactly how an old map can remain in
      // the download screen after its release manifest has been deleted.
      if (response.statusCode == 404) {
        _memory = null;
        _memoryLoadedAt = null;
        try {
          if (cache.existsSync()) await cache.delete();
        } catch (_) {}
        throw const FormatException('مانیفست نقشه در ریلیز maps-v4 پیدا نشد.');
      }

      // تشخیصی: تا الان اینجا هیچ ثبتی نمی‌شد — اگه گیت‌هاب مثلاً 404/302
      // به یک صفحه‌ی HTML redirect (نه raw JSON) برمی‌گردوند، یا body خیلی
      // کوتاه بود، بی‌صدا رد می‌شد و فهرست کشورهای همراه اپ نشان داده می‌شد،
      // بدون این‌که هیچ‌جا معلوم شود چرا لیستِ آنلاین واقعی لود نشده.
      
    } catch (error, stack) {
      // A missing maps-v4 manifest is authoritative: never fall back to an
      // older cached catalog in that case. Network errors, on the other hand,
      // may still use the stale cache for offline viewing.
      if (error is FormatException &&
          error.message.contains('maps-v4')) {
        rethrow;
      }
      
    }

    try {
      if (cache.existsSync()) {
        final cached = await cache.readAsString(encoding: utf8);
        final catalog = _parse(cached, fromNetwork: false);
        _memory = catalog;
        _memoryLoadedAt = DateTime.now();
        return catalog;
      }
    } catch (error, stack) {
      
    }

    // No bundled country list: the manifest is the only source of truth.
    // If the network is unavailable, use the last successfully downloaded
    // manifest cache; if there is no cache, surface the error to the UI.
    throw const FormatException('مانیفست نقشه در دسترس نیست.');
  }

  void dispose() => _client.close();
}
