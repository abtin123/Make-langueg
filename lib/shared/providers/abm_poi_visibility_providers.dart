import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../abtinmap/abm_models.dart';
import '../../features/settings/data/settings_repository.dart';
import '../../features/settings/presentation/settings_repository_provider.dart';

/// دسته‌های POI که کاربر روی نقشه فعال نگه داشته.
///
/// `null` یعنی همه‌ی دسته‌ها نمایش داده شوند (پیش‌فرض/رفتار قبلی — تا وقتی
/// [load] مقدار ذخیره‌شده را بخواند همین است). ست خالی یعنی کاربر همه‌ی
/// POIها را خاموش کرده. این مقدار برای لایهٔ POI محلیِ مبتنی بر ABM
/// روی MapLibre استفاده می‌شود.
final abmPoiVisibilityProvider =
    StateNotifierProvider<AbmPoiVisibilityNotifier, Set<int>?>(
  (ref) => AbmPoiVisibilityNotifier(ref),
);

class AbmPoiVisibilityNotifier extends StateNotifier<Set<int>?> {
  AbmPoiVisibilityNotifier(this._ref) : super(null);

  final Ref _ref;

  // مقدارِ ذخیره‌شده برای «نمایش همه‌ی دسته‌ها» — باید از رشته‌ی خالی
  // (که یعنی «هیچ‌کدام») متمایز باشد. قبلاً هر دو حالت با '' ذخیره
  // می‌شدند، پس بعد از یک‌بار زدنِ «نمایش همه» و ری‌استارت اپ، load()
  // آن را با «همه خاموش» اشتباه می‌گرفت و همه‌ی POIها ناپدید می‌شدند.
  static const _allMarker = '*';

  /// از appSettingsInitProvider در استارتاپ صدا زده می‌شود.
  Future<void> load() async {
    final repo = _ref.read(settingsRepositoryProvider);
    final raw = await repo.getValue(SettingsRepository.keyVisiblePoiKlasses);
    if (raw == null || raw == _allMarker) {
      state = null;
      return;
    }
    if (raw.isEmpty) {
      state = const <int>{};
      return;
    }
    state = raw
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toSet();
  }

  Future<void> setKlassEnabled(int klass, bool enabled) async {
    // وقتی state هنوز null است (یعنی «همه فعال‌اند»)، اولین تغییرِ کاربر
    // باید از روی لیست کاملِ دسته‌های قابل‌انتخاب شروع شود، نه از یک ست
    // خالی — وگرنه خاموش‌کردن یک دسته باعث می‌شد همه‌ی بقیه هم ناخواسته
    // مخفی شوند.
    final base = state ?? AbmKlass.selectablePoiKlasses.toSet();
    final next = Set<int>.from(base);
    if (enabled) {
      next.add(klass);
    } else {
      next.remove(klass);
    }
    state = next;
    await _persist(next);
  }

  Future<void> showAll() async {
    state = null;
    final repo = _ref.read(settingsRepositoryProvider);
    await repo.setValue(SettingsRepository.keyVisiblePoiKlasses, _allMarker);
  }

  /// همهٔ دسته‌ها را پنهان می‌کند و همان حالتِ ست خالی را پایدار نگه می‌دارد.
  Future<void> hideAll() async {
    state = const <int>{};
    await _persist(state!);
  }

  Future<void> _persist(Set<int> value) async {
    final repo = _ref.read(settingsRepositoryProvider);
    await repo.setValue(
      SettingsRepository.keyVisiblePoiKlasses,
      value.join(','),
    );
  }
}
