import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';

class SettingsRepository {
  final AppDatabase db;
  const SettingsRepository(this.db);

  static const keyVoiceEnabled = 'voice_enabled';
  static const keyVoiceVolume = 'voice_volume';
  static const keyVoiceRate = 'voice_rate';
  static const keyVoiceFirstAlertDistanceMeters =
      'voice_first_alert_distance_m';
  static const keyAlertsVoiceEnabled = 'alerts_voice_enabled';
  static const keyThemeMode = 'theme_mode';
  static const keyMapStyle = 'map_style';
  static const keyMapStyleNight = 'map_style_night';
  static const keyLanguage = 'language';
  static const keyActiveMapName = 'active_map_name';
  static const keyVehicleType = 'vehicle_type';

  /// ایندکس مدل سه‌بعدی خودروی انتخاب‌شده (در [vehicleModels]).
  static const keyVehicleModelIndex = 'vehicle_model_index';
  static const keyRouteColor = 'route_color';
  static const keyRouteWidth = 'route_width';
  static const keyRouteGlowEnabled = 'route_glow_enabled';
  static const keyRouteGlowIntensity = 'route_glow_intensity';
  static const keyAppColor = 'app_color';
  static const keyMapDisplayMode = 'map_display_mode';
  static const keyOfflinePaletteLight = 'offline_palette_light';
  static const keyOfflinePaletteDark = 'offline_palette_dark';
  static const keyElementDensity = 'element_density';

  /// حالت نمایش نقشه: '3d' (شیب‌دار) یا '2d' (از بالا).
  static const keyMapPerspective = 'map_perspective';

  /// کلیدِ واحدِ JSON برای همه‌ی تنظیمات ظاهری — نگاه کنید به
  /// [AppearanceSettings]. جایگزینِ keyPinColor..keyWeatherBgOpacity
  /// زیر که فقط برای سازگاری با دیتای نسخه‌های قدیمی نگه داشته شده‌اند
  /// (نگاه کنید به AppearanceSettingsNotifier._migrateLegacyIfNeeded).
  static const keyAppearanceSettings = 'appearance_settings_v2';

  // ====== تنظیمات ظاهری (جدید، بدون استایل پیش‌فرض) ======

  /// رنگ پیکان مسیریابی.
  static const keyPinColor = 'pin_color';

  /// سایه/هاله‌ی پیکان فعال باشد یا نه.
  static const keyPinShadow = 'pin_shadow';

  /// اندازه‌ی پیکان (درصد ۴۰ تا ۱۳۰).
  static const keyPinSize = 'pin_size';

  /// نوع خط مسیریابی: solid | dotted | dashed | dotDash.
  static const keyRouteLineStyle = 'route_line_style';

  /// زاویه‌ی دید نقشه در حالت ۳بعدی.
  static const keyMapTilt = 'map_tilt';

  /// آستانه‌ی زوم نمایش المان‌ها.
  static const keyElementMainRoadZoom = 'element_main_road_zoom';
  static const keyElementSubRoadZoom = 'element_sub_road_zoom';
  static const keyElementAlleyZoom = 'element_alley_zoom';

  /// رنگ مسیر (هگز) + رنگ گلو.
  static const keyRouteColorHex = 'route_color_hex';
  static const keyRouteColorGlowHex = 'route_color_glow_hex';

  /// فلگ سوییچ موتور مسیریابی: `abtinmap` (آفلاین .abm) یا `online`.
  static const keyRoutingEngine = 'routing_engine';

  /// دانلود خودکار نقشهٔ .abm در اولین اجرا.
  static const keyAbmAutoDownload = 'abm_auto_download';

  /// آخرین وضعیت دوربین نقشه تا بعد از بستن/باز کردن اپ همان نما برگردد.
  static const keyLastMapCenterLat = 'last_map_center_lat';
  static const keyLastMapCenterLng = 'last_map_center_lng';
  static const keyLastMapZoom = 'last_map_zoom';
  static const keyLastMapBearing = 'last_map_bearing';
  static const keyLastMapTilt = 'last_map_tilt';
  static const keyLastMapFollowVehicle = 'last_map_follow_vehicle';

  /// دسته‌های POI که کاربر روی نقشه فعال نگه داشته — CSV از کدهای
  /// `AbmKlass.poi*`. null/غایب یعنی همه‌ی دسته‌ها (پیش‌فرض قبلی).
  static const keyVisiblePoiKlasses = 'visible_poi_klasses';

  /// آیا ویجت شناور آب‌وهوا روی نقشه نمایش داده شود؟ پیش‌فرض false.
  /// ویجت و تنظیماتش (موقعیت/اندازه/پس‌زمینه) داخل تنظیمات ظاهری است.
  static const keyWeatherEnabled = 'weather_enabled';
  static const keyAirQualityEnabled = 'air_quality_enabled';
  static const keyClockEnabled = 'clock_enabled';
  static const keyBatteryEnabled = 'battery_enabled';

  /// گوشه‌ی نمایش ویجت آب‌وهوا روی نقشه: topLeft | topRight | bottomLeft | bottomRight.
  static const keyWeatherPosition = 'weather_position';

  /// اندازه‌ی ویجت آب‌وهوا (درصد ۷۰ تا ۱۵۰).
  static const keyWeatherSize = 'weather_size';

  /// رنگ پس‌زمینه‌ی ویجت آب‌وهوا.
  static const keyWeatherBgColor = 'weather_bg_color';

  /// شفافیت پس‌زمینه‌ی ویجت آب‌وهوا (۰ تا ۱).
  static const keyWeatherBgOpacity = 'weather_bg_opacity';

  Future<String?> getValue(String key) async {
    final row = await (db.select(
      db.appSettings,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setValue(String key, String value) async {
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: key, value: value),
        );
  }

  Future<bool> getBool(String key, {required bool fallback}) async {
    final v = await getValue(key);
    if (v == null) return fallback;
    return v == 'true';
  }

  Future<void> setBool(String key, bool value) =>
      setValue(key, value.toString());

  Future<double> getDouble(String key, {required double fallback}) async {
    final v = await getValue(key);
    if (v == null) return fallback;
    return double.tryParse(v) ?? fallback;
  }

  Future<void> setDouble(String key, double value) =>
      setValue(key, value.toString());
}
