import 'dart:async';
import 'dart:math' as math;
import '../../../core/geo/geo_types.dart';
import '../data/location_service.dart';
import 'vehicle_position_animator.dart';

/// آخرین لایه‌ی pipeline موقعیت‌یابیِ ناوبری:
///
///   Raw GPS → Accuracy Check → Kalman Filter → Map Matching → Navigation Position
///
/// دو مرحله‌ی اول («Raw GPS» و «Accuracy Check + Kalman Filter») داخل
/// [LocationService] انجام می‌شوند (به [LocationRepository] نگاه کنید).
/// این کلاس فقط مرحله‌ی «Map Matching» (snap به نزدیک‌ترین یالِ گراف
/// جاده‌ی آفلاین) و تحویل نتیجه به [VehiclePositionAnimator] (که خروجیِ
/// نهاییِ ۶۰fps برای Map UI را می‌سازد) را اضافه می‌کند. UI نباید مستقیم
/// stream خام LocationService را بخواند — باید از [positionStream] این
/// کلاس (یا از animatedVehiclePositionProvider که این را wrap می‌کند)
/// استفاده کند.
class NavigationPositionController {
  final Object? _graph;
  final VehiclePositionAnimator _animator = VehiclePositionAnimator();
  StreamSubscription<VehiclePosition>? _sub;
  int _latestFixSequence = 0;

  /// دقتِ گزارش‌شده‌ی GPS بالاتر از این حد، برای map matching به‌عنوانِ
  /// نامعتبر در نظر گرفته می‌شود — snap کردنِ یک فیکسِ ۱۰۰ متری خطا روی
  /// جاده می‌تواند بدتر از نمایشِ خامِ آن باشد.
  static const double _maxAccuracyForSnapM = 30.0;
  static const double _maxEstimatedAccuracyForSnapM = 120.0;

  /// اگر نزدیک‌ترین یال بیش از این فاصله دارد، یعنی احتمالاً ماشین توی
  /// پارکینگ/محوطه‌ای خارج از گراف است — snap نکن، موقعیتِ خام را نگه دار.
  static const double _maxSnapDistanceM = 25.0;
  static const double _maxEstimatedSnapDistanceM = 35.0;

  NavigationPositionController({Object? graph}) : _graph = graph;

  Stream<VehiclePosition> get positionStream => _animator.stream;

  bool get isRouteDriven => _animator.isRouteDriven;

  void setActiveRoute(List<LatLng> geometry, {VehiclePosition? anchor}) {
    _animator.setRoute(geometry, anchor: anchor);
  }

  void clearActiveRoute() {
    _animator.clearRoute();
  }

  /// Immediately leaves the planned route when the driver is confirmed to be
  /// on another road. The new GPS fix becomes the visual anchor while the
  /// route engine calculates the replacement route.
  void adoptGpsAnchor(VehiclePosition position) {
    _animator.adoptGpsAnchor(position);
  }

  void attach(Stream<VehiclePosition> rawFiltered) {
    // graph.snap ناهم‌زمان است. با اتصال به stream تازه، همهٔ snapshotهای
    // در حال پردازش از اتصال قبلی را نامعتبر می‌کنیم؛ وگرنه پاسخ دیررسِ آن‌ها
    // می‌تواند پس از بازشدن مجدد نقشه/تغییر گراف، خودرو را به جای قبلی بپراند.
    _latestFixSequence++;
    _sub?.cancel();
    _sub = rawFiltered.listen(_onFiltered);
  }

  void _onFiltered(VehiclePosition pos) {
    _latestFixSequence++;
    // Tile-based map matching has been removed. The Vector ABM routing graph
    // is consumed directly by the routing engine; the visual GPS pipeline
    // remains deterministic and never snaps to a legacy tile graph.
    _animator.onRawFix(pos);
  }

  double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  void dispose() {
    _latestFixSequence++;
    _sub?.cancel();
    _animator.dispose();
  }
}
