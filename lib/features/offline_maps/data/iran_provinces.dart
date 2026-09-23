import 'package:abtin_maps/core/geo/geo_types.dart';

class Province {
  final String id;
  final String name;
  final LatLngBounds bounds;
  final double areaFactor;

  Province({
    required this.id,
    required this.name,
    required this.bounds,
    this.areaFactor = 1,
  });
}

LatLngBounds _b(double swLat, double swLng, double neLat, double neLng) =>
    LatLngBounds(
      southwest: LatLng(swLat, swLng),
      northeast: LatLng(neLat, neLng),
    );

/// بستهٔ ملی: یک گراف/نقشه برای کل کشور تا مسیریابی بین‌استانی هم کار کند.
final Province kIranCountry = Province(
  id: 'iran',
  name: 'کل ایران (سراسری)',
  bounds: _b(24.5, 43.8, 40.1, 63.5),
  areaFactor: 25,
);

final List<Province> kIranProvinces = [
  Province(
      id: 'tehran',
      name: 'تهران',
      bounds: _b(35.0, 50.2, 36.3, 52.7),
      areaFactor: 1.2),
  Province(
      id: 'alborz',
      name: 'البرز',
      bounds: _b(35.6, 50.3, 36.5, 51.4),
      areaFactor: 0.6),
  Province(
      id: 'isfahan',
      name: 'اصفهان',
      bounds: _b(30.7, 49.0, 34.4, 55.5),
      areaFactor: 3.5),
  Province(
      id: 'fars',
      name: 'فارس',
      bounds: _b(27.0, 50.5, 31.4, 55.6),
      areaFactor: 3.2),
  Province(
      id: 'khorasan_razavi',
      name: 'خراسان رضوی',
      bounds: _b(33.8, 56.3, 37.7, 61.3),
      areaFactor: 3.0),
  Province(
      id: 'east_azerbaijan',
      name: 'آذربایجان شرقی',
      bounds: _b(36.6, 45.0, 39.4, 48.4),
      areaFactor: 1.6),
  Province(
      id: 'west_azerbaijan',
      name: 'آذربایجان غربی',
      bounds: _b(35.9, 43.5, 39.8, 47.4),
      areaFactor: 1.7),
  Province(
      id: 'khuzestan',
      name: 'خوزستان',
      bounds: _b(29.9, 47.6, 33.0, 50.9),
      areaFactor: 2.2),
  Province(
      id: 'mazandaran',
      name: 'مازندران',
      bounds: _b(35.9, 50.3, 36.9, 54.1),
      areaFactor: 1.0),
  Province(
      id: 'gilan',
      name: 'گیلان',
      bounds: _b(36.6, 48.5, 38.5, 50.6),
      areaFactor: 0.8),
  Province(
      id: 'kerman',
      name: 'کرمان',
      bounds: _b(26.5, 53.4, 32.0, 59.3),
      areaFactor: 4.5),
  Province(
      id: 'khorasan_south',
      name: 'خراسان جنوبی',
      bounds: _b(30.5, 57.0, 34.5, 60.9),
      areaFactor: 3.5),
  Province(
      id: 'sistan',
      name: 'سیستان و بلوچستان',
      bounds: _b(25.0, 58.8, 31.5, 63.4),
      areaFactor: 4.8),
  Province(
      id: 'yazd',
      name: 'یزد',
      bounds: _b(29.8, 52.6, 33.5, 57.1),
      areaFactor: 2.8),
  Province(
      id: 'hormozgan',
      name: 'هرمزگان',
      bounds: _b(25.4, 52.5, 28.9, 59.3),
      areaFactor: 2.5),
  Province(
      id: 'kermanshah',
      name: 'کرمانشاه',
      bounds: _b(33.7, 45.4, 35.4, 48.2),
      areaFactor: 1.1),
  Province(
      id: 'golestan',
      name: 'گلستان',
      bounds: _b(36.5, 53.5, 38.1, 56.4),
      areaFactor: 0.9),
  Province(
      id: 'lorestan',
      name: 'لرستان',
      bounds: _b(32.6, 46.8, 34.5, 50.3),
      areaFactor: 1.2),
  Province(
      id: 'hamadan',
      name: 'همدان',
      bounds: _b(34.0, 47.6, 35.8, 49.6),
      areaFactor: 0.9),
  Province(
      id: 'kurdistan',
      name: 'کردستان',
      bounds: _b(34.7, 45.5, 36.5, 48.2),
      areaFactor: 1.0),
  Province(
      id: 'markazi',
      name: 'مرکزی',
      bounds: _b(33.4, 48.9, 35.4, 51.3),
      areaFactor: 1.0),
  Province(
      id: 'qazvin',
      name: 'قزوین',
      bounds: _b(35.4, 48.8, 36.9, 50.6),
      areaFactor: 0.7),
  Province(
      id: 'zanjan',
      name: 'زنجان',
      bounds: _b(35.7, 47.1, 37.5, 49.5),
      areaFactor: 0.9),
  Province(
      id: 'ardabil',
      name: 'اردبیل',
      bounds: _b(37.2, 47.3, 39.8, 48.9),
      areaFactor: 0.9),
  Province(
      id: 'semnan',
      name: 'سمنان',
      bounds: _b(34.3, 51.7, 37.2, 57.2),
      areaFactor: 2.6),
  Province(
      id: 'qom',
      name: 'قم',
      bounds: _b(34.2, 50.2, 35.2, 51.6),
      areaFactor: 0.6),
  Province(
      id: 'chaharmahal',
      name: 'چهارمحال و بختیاری',
      bounds: _b(31.3, 49.5, 32.7, 51.5),
      areaFactor: 0.7),
  Province(
      id: 'kohgiluyeh',
      name: 'کهگیلویه و بویراحمد',
      bounds: _b(30.0, 49.7, 31.5, 51.6),
      areaFactor: 0.7),
  Province(
      id: 'bushehr',
      name: 'بوشهر',
      bounds: _b(27.4, 50.0, 30.3, 52.6),
      areaFactor: 1.3),
  Province(
      id: 'ilam',
      name: 'ایلام',
      bounds: _b(32.0, 45.4, 34.4, 48.4),
      areaFactor: 0.8),
  Province(
      id: 'khorasan_north',
      name: 'خراسان شمالی',
      bounds: _b(36.5, 55.8, 38.2, 58.5),
      areaFactor: 0.9),
];

/// همهٔ ردیف‌های قابل دانلود؛ بستهٔ ملی همیشه اولِ فهرست است.
final List<Province> kIranRegions = <Province>[kIranCountry, ...kIranProvinces];

Province? provinceById(String id) {
  for (final p in kIranRegions) {
    if (p.id == id) return p;
  }
  return null;
}
