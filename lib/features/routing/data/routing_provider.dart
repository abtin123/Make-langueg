import 'package:abtin_maps/core/geo/geo_types.dart';

import 'routing_service.dart';

/// موتور مسیریابی انتخاب‌شده در تنظیمات (ذخیره در AppSettings/drift).
enum RoutingEngine {
  /// موتور آفلاین اختصاصی ABTINMAP (.abm).
  abtinmap,

  /// نقشه و مسیریابی برخط بر پایهٔ داده‌های OpenStreetMap/OSRM.
  online,
}

extension RoutingEngineX on RoutingEngine {
  String get storageValue => name;

  String get label => switch (this) {
        RoutingEngine.abtinmap => 'آبتین‌مپ (آفلاین)',
        RoutingEngine.online => 'نقشه و مسیریابی آنلاین',
      };

  static RoutingEngine parse(String? value) => RoutingEngine.values.firstWhere(
        (engine) => engine.storageValue == value,
        orElse: () => RoutingEngine.online,
      );
}

/// اینترفیس واحدی که همه‌ی لایه‌های بالاتر اپ با آن کار می‌کنند.
/// هر دو پیاده‌سازی (آنلاین و ABTINMAP) خروجی یکسان [RouteInfo] می‌دهند.
abstract class RoutingProvider {
  /// شناسه‌ی موتور.
  RoutingEngine get engine;

  /// نام قابل نمایش.
  String get displayName;

  /// آیا این موتور بدون اینترنت قابل استفاده است؟
  bool get isOffline;

  /// آیا داده‌ی لازم (نقشه/گراف) روی دستگاه آماده است؟
  Future<bool> isReady();

  /// آخرین خطا (پیام فارسی، برای نمایش در UI).
  String? get lastError;

  /// محاسبه‌ی مسیر. اگر نشد null و [lastError] ست می‌شود.
  Future<RouteInfo?> calculateRoute({
    required LatLng origin,
    required LatLng destination,
    bool offlineOnly = false,
  });
}
