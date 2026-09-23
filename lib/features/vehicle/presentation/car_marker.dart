import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import 'vehicle_provider.dart';

/// محیطِ نوریِ HDR (بدونِ skybox صریح؛ model_viewer_plus خودش پس‌زمینه را
/// شفاف نگه می‌دارد و فقط از exposure/shadow پیش‌فرض استفاده می‌کند).

/// اصلاحِ زاویهٔ چرخشِ افقیِ دوربین دور خودرو، اگر جلوی مدلِ GLB با محورِ
/// پیش‌فرض هم‌راستا نبود. پیش‌فرض صفر؛ بعد از دیدنِ مدل روی دستگاهِ واقعی
/// در صورت نیاز فقط همین عدد برای همان ایندکس تغییر کند.
const _yawCorrectionDegrees = <double>[0.0, 0.0, 0.0, 0.0];

/// زاویهٔ چرخشِ صفحه‌ایِ مکان‌نمای خودرو نسبت به heading جغرافیایی/نقشه.
double vehicleScreenRotationDegrees(double headingDeg) {
  final normalized = headingDeg.isFinite ? headingDeg : 0.0;
  final value = normalized % 360.0;
  return value < 0 ? value + 360.0 : value;
}

/// camera-orbit مدل‌ویوئر را از (angleDegrees, sizePercent) می‌سازد.
///
/// model_viewer_plus (google model-viewer) خودش auto-frame/normalize
/// می‌کند، پس دیگر نیازی به حدسِ فاصلهٔ دوربین برای هر GLB نیست؛ فقط
/// theta/phi/radius به‌صورتِ رشتهٔ camera-orbit پاس داده می‌شود.
/// angle=0 یعنی «از بالا» → phi نزدیکِ ۹۰ درجه (دوربین بالای صحنه). angle=90
/// یعنی «از پشتِ خودرو» → phi نزدیکِ ۱۲ درجه (نزدیکِ افق).
String _cameraOrbitFor({
  required int modelIndex,
  required double angleDegrees,
  required double sizePercent,
}) {
  final angle = angleDegrees.clamp(0, 90).toDouble();
  final size = sizePercent.clamp(40, 220).toDouble();

  // model-viewer: phi=90° is the vertical/top view, while a small phi
  // gives a low rear/driver perspective. Keep the UI direction intuitive:
  // 0° -> top, 90° -> rear.
  final phiDeg = 90.0 - (angle / 90.0) * 78.0;
  // پایهٔ ۱۸۰ درجه یعنی «نگاه از پشتِ خودرو» در نزدیکِ افق (angle=90). بدونِ
  // این آفست، چون _yawCorrectionDegrees پیش‌فرض صفر است، دوربین دقیقاً از
  // جلوی خودرو نگاه می‌کرد (باگِ گزارش‌شده). هر مدل با ایندکسِ خودش در
  // _yawCorrectionDegrees قابلِ ریزتنظیم است.
  final thetaDeg = 180.0 +
      _yawCorrectionDegrees[modelIndex.clamp(0, vehicleModels.length - 1)];

  // اندازهٔ خودرو باید با افزایش اسلایدر به‌صورت ملایم تغییر کند.
  // فرمول قبلی در ۱۵۰٪ شعاع را تا ۷۰٪ پایین می‌آورد و مدل را بیش از حد
  // به دوربین نزدیک می‌کرد؛ نتیجه یک خودرو بسیار بزرگ و غیرطبیعی بود.
  // sqrt باعث می‌شود افزایش اندازه تدریجی باشد و در بزرگ‌نمایی‌های بالا
  // مدل همچنان تناسب طبیعی خودش را حفظ کند.
  // The map overlay has its own fixed hit/anchor box. Visual size must not
  // change that box (otherwise changing the slider also changes the vehicle's
  // projected position on the map). Scale the model itself instead.
  const radiusPercent = 132.0;

  return '${thetaDeg}deg ${phiDeg}deg $radiusPercent%';
}

/// مکان‌نمای واقعیِ سه‌بعدیِ خودرو با موتور model-viewer (WebGL) — از
/// زاویه‌ای بینِ «کاملاً از بالا» و «از پشتِ خودرو» که با
/// [cameraAngleDegrees] قابل‌تنظیم است (۰=از بالا، ۹۰=از پشت)؛ اندازهٔ
/// ظاهری با [sizePercent]؛ چرخشِ خودرو نسبت به جاده با [headingDeg].
///
/// نکتهٔ مهم: این ویجت به‌صورت پیش‌فرض [interactive]=false دارد، یعنی لمسِ
/// داخلِ آن هیچ چرخشی روی مدل ایجاد نمی‌کند. زاویهٔ دوربین فقط از طریق
/// [cameraAngleDegrees] (که از اسلایدرِ تنظیمات می‌آید) تغییر می‌کند. اگر
/// نیاز به چرخشِ لمسی بود، [interactive] را true کنید — ولی در عمل هیچ‌جایِ
/// اپ به این حالت نیاز ندارد.
class CarMarker3D extends StatelessWidget {
  const CarMarker3D({
    super.key,
    required this.size,
    required this.modelIndex,
    this.headingDeg = 0,
    this.cameraAngleDegrees = 0,
    this.sizePercent = 80,
    this.interactive = false,
  });

  /// اندازهٔ باکسِ ویجت بر حسب پیکسل. اندازهٔ مدل داخل آن متناسب با
  /// [sizePercent] تنظیم می‌شود؛ یعنی هرچه [sizePercent] بالاتر، خودرو
  /// بزرگ‌تر داخل همین باکس دیده می‌شود و هیچ‌وقت از آن بیرون نمی‌زند.
  final double size;
  final int modelIndex;

  /// چرخشِ خودرو نسبت به شمال نقشه (درجه). برای حالتِ ناوبری، این مقدار
  /// از heading جغرافیایی خودرو منهای bearing فعلی نقشه به دست می‌آید تا
  /// خودرو همیشه در امتدادِ جاده (نه دیواره‌های نقشه) قرار بگیرد.
  final double headingDeg;

  /// زاویهٔ عمودیِ دوربین: ۰ یعنی «از بالا»، ۹۰ یعنی «از پشتِ خودرو».
  /// فقط اسلایدرِ تنظیمات این مقدار را عوض می‌کند.
  final double cameraAngleDegrees;

  /// درصدِ اندازهٔ ظاهریِ مدل داخل باکس (۴۰ تا ۲۲۰). هرچه بزرگ‌تر، شعاعِ
  /// دوربین کمتر می‌شود تا خودرو بزرگ‌تر دیده شود، ولی auto-frame مدل‌ویوئر
  /// تضمین می‌کند که هیچ‌وقت از باکس بیرون نزند.
  final double sizePercent;

  /// اگر true باشد، لمس و چرخش روی خود مدل فعال می‌شود. در حالتِ عادی
  /// false است؛ فقط اسلایدر تنظیمات می‌تواند نمای دوربین را عوض کند.
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final safeIndex = modelIndex.clamp(0, vehicleModels.length - 1);
    final cameraOrbit = _cameraOrbitFor(
      modelIndex: safeIndex,
      angleDegrees: cameraAngleDegrees,
      sizePercent: 100,
    );

    // Keep ModelViewer's State stable while navigation updates arrive.
    // model_viewer_plus initializes its native/web controller asynchronously;
    // replacing the widget during that async gap can make its internal
    // _initController call setState() after disposal.
    final rebuildKey = ValueKey('car-$safeIndex');

    // The marker is always the real GLB vehicle. ModelViewer's eager loading
    // starts fetching immediately instead of waiting for interaction/viewport
    // heuristics. No arrow is substituted for the car.
    final viewer = ClipRect(
      child: ModelViewer(
        key: rebuildKey,
        src: vehicleModels[safeIndex],
        alt: 'Vehicle',
        backgroundColor: Colors.transparent,
        cameraOrbit: cameraOrbit,
        cameraControls: interactive,
        disableZoom: !interactive,
        autoRotate: false,
        ar: false,
        // Eager loading makes the controller initialize immediately. During
        // rapid map/navigation rebuilds this can race with disposal in
        // model_viewer_plus. Lazy loading is safer and the widget remains
        // mounted by the map views.
        loading: Loading.lazy,
        reveal: Reveal.auto,
        shadowIntensity: 0,
      ),
    );

    // جهت خودرو همیشه نسبت به جهت فعلیِ نقشه/صفحه اعمال می‌شود. در حالت
    // follow، bearing نقشه با heading خودرو یکی است و این مقدار صفر می‌شود؛
    // در حالت آزاد، اختلاف heading و bearing باعث می‌شود خودرو همچنان دقیقاً
    // در امتداد جاده بماند.
    // قبلاً با نزدیک‌شدن دوربین به نمای 3D این چرخش عملاً به صفر می‌رسید؛
    // در نتیجه خودرو در نمای مایل دیگر با مسیر هم‌جهت نبود.
    final visualScale = (sizePercent.clamp(45.0, 150.0) / 100.0).toDouble();

    return SizedBox.square(
      dimension: size,
      child: IgnorePointer(
        ignoring: !interactive,
        child: Transform.scale(
          scale: visualScale,
          alignment: Alignment.bottomCenter,
          child: Transform.rotate(
            angle: vehicleScreenRotationDegrees(headingDeg) * math.pi / 180.0,
            alignment: Alignment.center,
            child: viewer,
          ),
        ),
      ),
    );
  }
}
