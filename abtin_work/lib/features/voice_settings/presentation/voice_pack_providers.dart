import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/voice_pack_catalog.dart';
import '../../settings/presentation/settings_repository_provider.dart';
import '../../settings/data/settings_repository.dart';

final voicePackServiceProvider = Provider<VoicePackService>((ref) {
  return VoicePackService();
});

class _DownloadedVoiceSelectionNotifier extends StateNotifier<String?> {
  _DownloadedVoiceSelectionNotifier(this._repo, this._key) : super(null) {
    _load();
  }

  final SettingsRepository _repo;
  final String _key;

  Future<void> _load() async {
    final stored = await _repo.getValue(_key);
    state = stored == null || stored.isEmpty ? null : stored;
  }

  Future<void> set(String? fileName) async {
    state = fileName;
    await _repo.setValue(_key, fileName ?? '');
  }
}

/// تنها صدای راهنمای فعال: نام واقعی فایل دانلودشده، یا null اگر هنوز چیزی
/// از بخش دانلودها دریافت نشده باشد.
final activeVoicePackProvider =
    StateNotifierProvider<_DownloadedVoiceSelectionNotifier, String?>((ref) {
  return _DownloadedVoiceSelectionNotifier(
      ref.watch(settingsRepositoryProvider), 'active_downloaded_voice_file');
});

/// صدای هشدار مستقل از راهنمای مسیر، باز هم فقط با نام فایل دانلودشده.
final alertVoicePackProvider =
    StateNotifierProvider<_DownloadedVoiceSelectionNotifier, String?>((ref) {
  return _DownloadedVoiceSelectionNotifier(
      ref.watch(settingsRepositoryProvider), 'active_downloaded_alert_file');
});

/// شمارندهٔ تازه‌سازی دستیِ فهرست بسته‌های صوتی (دکمهٔ «تازه‌سازی» در صفحهٔ
/// صدا). فقط با تغییر همین مقدار، مانیفست بدون توجه به کشِ محلی دوباره از
/// شبکه خوانده می‌شود؛ ورود/خروج از صفحه به‌تنهایی هرگز این کار را نمی‌کند.
final voicePackCatalogRefreshProvider = StateProvider<int>((ref) => 0);

final voicePackManifestProvider =
    FutureProvider<List<VoicePackRemote>>((ref) async {
  final refreshCount = ref.watch(voicePackCatalogRefreshProvider);
  return ref
      .watch(voicePackServiceProvider)
      .fetchManifest(forceRefresh: refreshCount > 0);
});

final installedVoicePacksProvider =
    StateNotifierProvider<InstalledVoicePacksNotifier, Set<String>>((ref) {
  return InstalledVoicePacksNotifier(ref.watch(voicePackServiceProvider));
});

class InstalledVoicePacksNotifier extends StateNotifier<Set<String>> {
  InstalledVoicePacksNotifier(this._service) : super(const {}) {
    _load();
  }

  final VoicePackService _service;

  Future<void> _load() async {
    state = await _service.installedFiles();
  }

  Future<void> refresh() => _load();
}

final voicePackDownloadProgressProvider =
    StateProvider<Map<String, double>>((ref) => {});
final voicePackDownloadErrorProvider =
    StateProvider<Map<String, String>>((ref) => {});

Future<void> downloadVoicePack(WidgetRef ref, VoicePackRemote pack) async {
  final service = ref.read(voicePackServiceProvider);
  ref.read(voicePackDownloadErrorProvider.notifier).update(
        (map) => {...map}..remove(pack.name),
      );
  ref.read(voicePackDownloadProgressProvider.notifier).update(
        (map) => {...map, pack.name: 0.0},
      );
  try {
    await service.download(
      pack,
      onProgress: (progress) {
        ref.read(voicePackDownloadProgressProvider.notifier).update(
              (map) => {...map, pack.name: progress},
            );
      },
    );
    await ref.read(installedVoicePacksProvider.notifier).refresh();
    // دانلودشدن و فعال‌بودن دو وضعیت مستقل‌اند. پس از دانلود فقط نشان
    // «روی دستگاه» دیده می‌شود؛ کاربر باید همان بسته را صریحاً انتخاب کند
    // تا تیک فعال و استفادهٔ ناوبری به آن منتقل شود.
  } catch (error) {
    ref.read(voicePackDownloadErrorProvider.notifier).update(
          (map) => {...map, pack.name: error.toString()},
        );
  } finally {
    ref.read(voicePackDownloadProgressProvider.notifier).update(
          (map) => {...map}..remove(pack.name),
        );
  }
}

Future<void> deleteVoicePack(WidgetRef ref, VoicePackRemote pack) async {
  final service = ref.read(voicePackServiceProvider);
  await service.delete(pack);
  if (ref.read(activeVoicePackProvider) == pack.name) {
    await ref.read(activeVoicePackProvider.notifier).set(null);
  }
  if (ref.read(alertVoicePackProvider) == pack.name) {
    await ref.read(alertVoicePackProvider.notifier).set(null);
  }
  await ref.read(installedVoicePacksProvider.notifier).refresh();
}
