import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:abtin_maps/core/geo/geo_types.dart';

/// یک نتیجهٔ جستجوی مکان.
class PlaceSearchResult {
  final String name;
  final String? region;
  final LatLng point;
  final bool isOffline;
  final double? distanceMeters;

  const PlaceSearchResult({
    required this.name,
    required this.point,
    this.region,
    this.isOffline = false,
    this.distanceMeters,
  });
}

/// محدودهٔ جغرافیایی جستجو.
class SearchArea {
  final String? city;
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;
  final LatLng center;

  const SearchArea({
    required this.city,
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
    required this.center,
  });

  String get viewbox => '$minLng,$maxLat,$maxLng,$minLat';

  bool contains(LatLng p) =>
      p.latitude >= minLat &&
      p.latitude <= maxLat &&
      p.longitude >= minLng &&
      p.longitude <= maxLng;
}

/// جستجوی مکان با محدودهٔ شهری واقعی.
///
/// قانون اصلی:
/// 1) اگر کاربر نام شهر را صریحاً در عبارت بنویسد، همان شهر محدودهٔ جستجو است.
/// 2) در غیر این صورت شهر فعلی کاربر از GPS + reverse geocoding تعیین می‌شود.
/// 3) نتایج فقط داخل همان محدوده پذیرفته می‌شوند و بر اساس فاصله مرتب می‌شوند.
class PlaceSearchService {
  static const String _searchUrl = 'https://nominatim.openstreetmap.org/search';
  static const String _reverseUrl =
      'https://nominatim.openstreetmap.org/reverse';
  static const String _photonSearchUrl = 'https://photon.komoot.io/api/';

  final http.Client _client;
  final Map<String, SearchArea?> _areaCache = <String, SearchArea?>{};

  PlaceSearchService({http.Client? client}) : _client = client ?? http.Client();

  /// شهر هدف جستجو را بدون اجرای خودِ جستجو برمی‌گرداند.
  /// اگر نام شهر در متن باشد همان شهر؛ در غیر این صورت شهر GPS.
  Future<String?> resolveSearchCity(
    String query, {
    double? biasLat,
    double? biasLng,
  }) async {
    final explicit = await _findExplicitCity(query.trim());
    if (explicit?.city != null) return explicit!.city;
    if (biasLat == null || biasLng == null) return null;
    final current = await _findCurrentCity(LatLng(biasLat, biasLng));
    return current?.city;
  }

  Future<List<PlaceSearchResult>> searchOnline(
    String query, {
    double? biasLat,
    double? biasLng,
    int limit = 12,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final current =
        biasLat != null && biasLng != null ? LatLng(biasLat, biasLng) : null;

    // اول بررسی می‌کنیم آیا نام یک شهر ایرانی صریحاً در متن آمده است.
    final explicitArea = await _findExplicitCity(trimmed);
    final area = explicitArea ??
        (current == null ? null : await _findCurrentCity(current));

    final city = area?.city;
    final params = <String, String>{
      'q': city == null ? '$trimmed, Iran' : '$trimmed, $city, Iran',
      'format': 'jsonv2',
      'addressdetails': '1',
      'limit': '30',
      'accept-language': 'fa',
      'countrycodes': 'ir',
      'dedupe': '1',
    };

    if (area != null) {
      // bounded=1 مهم است: viewbox فقط bias نباشد و نتیجهٔ شهر دیگر وارد نشود.
      params['viewbox'] = area.viewbox;
      params['bounded'] = '1';
    }

    final uri = Uri.parse(_searchUrl).replace(queryParameters: params);
    late final http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: const {
          'User-Agent': 'AbtinMaps/1.0 (contact: support@abtinmaps.app)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      return _searchPhoton(trimmed, current: current, limit: limit);
    }

    if (response.statusCode != 200) {
      return _searchPhoton(trimmed, current: current, limit: limit);
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    final results = <PlaceSearchResult>[];

    for (final raw in data) {
      final item = raw as Map<String, dynamic>;
      final lat = double.tryParse('${item['lat']}');
      final lon = double.tryParse('${item['lon']}');
      if (lat == null || lon == null) continue;

      final point = LatLng(lat, lon);
      final address = item['address'] is Map
          ? Map<String, dynamic>.from(item['address'] as Map)
          : <String, dynamic>{};
      final resultCity = _cityFromAddress(address);

      // حتی بعد از bounded=1 هم فیلتر نهایی را انجام می‌دهیم تا هیچ نتیجهٔ
      // متعلق به شهر دیگر به UI نرسد.
      if (area != null && !area.contains(point)) continue;
      if (area?.city != null &&
          resultCity != null &&
          !_samePlaceName(resultCity, area!.city!)) {
        continue;
      }

      final distance = current == null
          ? _distanceMeters(area?.center ?? point, point)
          : _distanceMeters(
              explicitArea == null ? current : area!.center,
              point,
            );

      final region = _regionFromAddress(address, resultCity);
      results.add(PlaceSearchResult(
        name: _displayName(item, trimmed),
        region: region,
        point: point,
        distanceMeters: distance,
      ));
    }

    results.sort((a, b) {
      final da = a.distanceMeters ?? double.infinity;
      final db = b.distanceMeters ?? double.infinity;
      final byDistance = da.compareTo(db);
      if (byDistance != 0) return byDistance;
      return a.name.compareTo(b.name);
    });

    return results.take(limit).toList(growable: false);
  }

  Future<List<PlaceSearchResult>> _searchPhoton(
    String query, {
    required LatLng? current,
    required int limit,
  }) async {
    final params = <String, String>{
      'q': query,
      'limit': '${math.max(limit, 12)}',
      'lang': 'default',
    };
    if (current != null) {
      params['lat'] = '${current.latitude}';
      params['lon'] = '${current.longitude}';
    }
    try {
      final response = await _client.get(
        Uri.parse(_photonSearchUrl).replace(queryParameters: params),
        headers: const {
          'User-Agent': 'AbtinMaps/1.0 (contact: support@abtinmaps.app)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return const [];
      final root = jsonDecode(response.body) as Map<String, dynamic>;
      final features = root['features'];
      if (features is! List) return const [];
      final results = <PlaceSearchResult>[];
      for (final raw in features) {
        if (raw is! Map) continue;
        final feature = Map<String, dynamic>.from(raw);
        final geometry = feature['geometry'];
        final coordinates = geometry is Map ? geometry['coordinates'] : null;
        if (coordinates is! List || coordinates.length < 2) continue;
        final lon = double.tryParse('${coordinates[0]}');
        final lat = double.tryParse('${coordinates[1]}');
        if (lat == null || lon == null) continue;
        final properties = feature['properties'] is Map
            ? Map<String, dynamic>.from(feature['properties'] as Map)
            : <String, dynamic>{};
        final name = (properties['name'] ??
                properties['street'] ??
                properties['city'] ??
                query)
            .toString()
            .trim();
        final region = [
          properties['city'],
          properties['state'],
        ].whereType<String>().where((e) => e.trim().isNotEmpty).join('، ');
        final point = LatLng(lat, lon);
        results.add(PlaceSearchResult(
          name: name.isEmpty ? query : name,
          region: region.isEmpty ? null : region,
          point: point,
          distanceMeters:
              current == null ? null : _distanceMeters(current, point),
        ));
      }
      results.sort((a, b) => (a.distanceMeters ?? double.infinity)
          .compareTo(b.distanceMeters ?? double.infinity));
      return results.take(limit).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<SearchArea?> _findCurrentCity(LatLng current) async {
    final key =
        'gps:${current.latitude.toStringAsFixed(3)},${current.longitude.toStringAsFixed(3)}';
    if (_areaCache.containsKey(key)) return _areaCache[key];

    try {
      final uri = Uri.parse(_reverseUrl).replace(queryParameters: {
        'lat': '${current.latitude}',
        'lon': '${current.longitude}',
        'format': 'jsonv2',
        'addressdetails': '1',
        'zoom': '10',
        'accept-language': 'fa',
      });
      final response = await _client.get(uri, headers: const {
        'User-Agent': 'AbtinMaps/1.0 (offline-navigation-app)',
      }).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;

      final item = jsonDecode(response.body) as Map<String, dynamic>;
      final address = item['address'] is Map
          ? Map<String, dynamic>.from(item['address'] as Map)
          : <String, dynamic>{};
      final city = _cityFromAddress(address);
      if (city == null || city.isEmpty) return null;

      final bbox = _bbox(item['boundingbox']);
      if (bbox != null) {
        final area = SearchArea(
          city: city,
          minLat: bbox[0],
          maxLat: bbox[1],
          minLng: bbox[2],
          maxLng: bbox[3],
          center: current,
        );
        _areaCache[key] = area;
        return area;
      }

      final searched = await _findCityByName(city);
      _areaCache[key] = searched;
      return searched;
    } catch (_) {
      _areaCache[key] = null;
      return null;
    }
  }

  Future<SearchArea?> _findExplicitCity(String query) async {
    // نام‌های یک تا سه‌کلمه‌ای را بررسی می‌کنیم؛ featuretype=city باعث می‌شود
    // «رستوران» یا «خیابان» به‌عنوان شهر اشتباه گرفته نشود.
    final tokens = query
        .replaceAll(RegExp(r'[,،;؛/\\]'), ' ')
        .split(RegExp(r'\s+'))
        .where((e) => e.trim().length >= 2)
        .toList();
    final candidates = <String>[];
    for (var n = math.min(3, tokens.length); n >= 1; n--) {
      for (var i = 0; i + n <= tokens.length; i++) {
        candidates.add(tokens.sublist(i, i + n).join(' '));
      }
    }

    for (final candidate in candidates) {
      final area = await _findCityByName(candidate);
      if (area != null && _containsPhrase(query, area.city!)) return area;
    }
    return null;
  }

  Future<SearchArea?> _findCityByName(String city) async {
    final normalized = _normalize(city);
    if (normalized.isEmpty) return null;
    final key = 'city:$normalized';
    if (_areaCache.containsKey(key)) return _areaCache[key];

    try {
      final uri = Uri.parse(_searchUrl).replace(queryParameters: {
        'q': '$city, Iran',
        'format': 'jsonv2',
        'addressdetails': '1',
        'limit': '3',
        'featuretype': 'city',
        'countrycodes': 'ir',
        'accept-language': 'fa',
      });
      final response = await _client.get(uri, headers: const {
        'User-Agent': 'AbtinMaps/1.0 (offline-navigation-app)',
      }).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as List<dynamic>;
      for (final raw in data) {
        final item = raw as Map<String, dynamic>;
        final address = item['address'] is Map
            ? Map<String, dynamic>.from(item['address'] as Map)
            : <String, dynamic>{};
        final foundCity =
            _cityFromAddress(address) ?? (item['name'] as String?);
        if (foundCity == null || !_samePlaceName(foundCity, city)) continue;
        final bbox = _bbox(item['boundingbox']);
        if (bbox == null) continue;
        final lat = double.tryParse('${item['lat']}');
        final lon = double.tryParse('${item['lon']}');
        if (lat == null || lon == null) continue;
        final area = SearchArea(
          city: foundCity,
          minLat: bbox[0],
          maxLat: bbox[1],
          minLng: bbox[2],
          maxLng: bbox[3],
          center: LatLng(lat, lon),
        );
        _areaCache[key] = area;
        return area;
      }
    } catch (_) {}

    _areaCache[key] = null;
    return null;
  }

  String? _cityFromAddress(Map<String, dynamic> address) {
    for (final key in const [
      'city',
      'town',
      'municipality',
      'city_district',
      'village',
    ]) {
      final value = address[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  String? _regionFromAddress(Map<String, dynamic> address, String? city) {
    final values = <String>[];
    if (city != null && city.isNotEmpty) values.add(city);
    final state = address['state'];
    if (state is String &&
        state.isNotEmpty &&
        !_samePlaceName(state, city ?? '')) {
      values.add(state);
    }
    return values.isEmpty ? null : values.join('، ');
  }

  String _displayName(Map<String, dynamic> item, String fallback) {
    final name = item['name'];
    if (name is String && name.trim().isNotEmpty) return name.trim();
    final display = item['display_name'];
    if (display is String && display.trim().isNotEmpty) {
      return display.split('،').first.trim();
    }
    return fallback;
  }

  List<double>? _bbox(dynamic raw) {
    if (raw is! List || raw.length < 4) return null;
    final south = double.tryParse('${raw[0]}');
    final north = double.tryParse('${raw[1]}');
    final west = double.tryParse('${raw[2]}');
    final east = double.tryParse('${raw[3]}');
    if ([south, north, west, east].any((e) => e == null)) return null;
    return [south!, north!, west!, east!];
  }

  bool _containsPhrase(String query, String city) =>
      _normalize(query).contains(_normalize(city));

  String _normalize(String value) => value
      .replaceAll('ي', 'ی')
      .replaceAll('ك', 'ک')
      .replaceAll(RegExp(r'[\u064B-\u065F]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();

  bool _samePlaceName(String a, String b) => _normalize(a) == _normalize(b);

  double _distanceMeters(LatLng a, LatLng b) {
    const radius = 6371000.0;
    final p1 = a.latitude * math.pi / 180;
    final p2 = b.latitude * math.pi / 180;
    final dp = (b.latitude - a.latitude) * math.pi / 180;
    final dl = (b.longitude - a.longitude) * math.pi / 180;
    final h = math.sin(dp / 2) * math.sin(dp / 2) +
        math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    return 2 * radius * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }
}
