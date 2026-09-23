import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/data/settings_repository.dart';
import '../../features/settings/presentation/settings_repository_provider.dart';

/// سطح نمایش یک اعلان داخلی. اعلان‌های موفق و اطلاع‌رسانی مزاحم مسیریابی
/// نمی‌شوند؛ warning/error ماندگاری بیشتری در بنر بالای صفحه دارند.
enum AppNoticeLevel { success, info, warning, error }

@immutable
class AppNotice {
  const AppNotice({
    required this.id,
    required this.title,
    required this.message,
    required this.level,
    required this.createdAt,
    this.read = false,
  });

  final String id;
  final String title;
  final String message;
  final AppNoticeLevel level;
  final DateTime createdAt;
  final bool read;

  AppNotice copyWith({bool? read}) => AppNotice(
        id: id,
        title: title,
        message: message,
        level: level,
        createdAt: createdAt,
        read: read ?? this.read,
      );

  Map<String, Object> toJson() => <String, Object>{
        'id': id,
        'title': title,
        'message': message,
        'level': level.name,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'read': read,
      };

  factory AppNotice.fromJson(Map<String, dynamic> json) {
    final levelName = json['level'] as String?;
    final level = AppNoticeLevel.values.firstWhere(
      (value) => value.name == levelName,
      orElse: () => AppNoticeLevel.info,
    );
    return AppNotice(
      id: json['id'] as String? ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      title: json['title'] as String? ?? 'اعلان برنامه',
      message: json['message'] as String? ?? '',
      level: level,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
              DateTime.now(),
      read: json['read'] == true,
    );
  }
}

/// تاریخچهٔ کوتاه و محلی اعلان‌ها. فقط رخدادهای داخل اپ نگه‌داری می‌شوند؛
/// این کلاس به notification سیستم‌عامل یا اینترنت وابسته نیست.
class AppNoticeNotifier extends StateNotifier<List<AppNotice>> {
  AppNoticeNotifier(this._ref) : super(const <AppNotice>[]);

  static const _storageKey = 'app_notice_history_v1';
  static const _limit = 40;
  final Ref _ref;

  SettingsRepository get _repo => _ref.read(settingsRepositoryProvider);

  Future<void> load() async {
    final raw = await _repo.getValue(_storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final values = jsonDecode(raw) as List<dynamic>;
      state = values
          .whereType<Map<String, dynamic>>()
          .map(AppNotice.fromJson)
          .take(_limit)
          .toList(growable: false);
    } catch (_) {
      // تاریخچهٔ خراب نباید راه‌اندازی نقشه/ناوبری را مختل کند.
      state = const <AppNotice>[];
    }
  }

  Future<void> show({
    required String title,
    required String message,
    AppNoticeLevel level = AppNoticeLevel.info,
  }) async {
    final notice = AppNotice(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      message: message,
      level: level,
      createdAt: DateTime.now(),
    );
    state = <AppNotice>[notice, ...state].take(_limit).toList(growable: false);
    await _persist();
  }

  Future<void> markAllRead() async {
    if (state.every((notice) => notice.read)) return;
    state = state
        .map((notice) => notice.copyWith(read: true))
        .toList(growable: false);
    await _persist();
  }

  Future<void> clear() async {
    state = const <AppNotice>[];
    await _repo.setValue(_storageKey, '[]');
  }

  Future<void> _persist() => _repo.setValue(
        _storageKey,
        jsonEncode(
            state.map((notice) => notice.toJson()).toList(growable: false)),
      );
}

final appNoticeProvider =
    StateNotifierProvider<AppNoticeNotifier, List<AppNotice>>(
  (ref) => AppNoticeNotifier(ref),
);

final unreadAppNoticeCountProvider = Provider<int>(
  (ref) => ref.watch(appNoticeProvider).where((notice) => !notice.read).length,
);
