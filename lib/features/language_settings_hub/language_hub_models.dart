import 'package:flutter/material.dart';
import '../../core/localization/locale_flags.dart';

/// آیتم یکسان‌شده برای نمایش ردیف دانلود، صرف‌نظر از این‌که
/// پشت صحنه از map_catalog، voice_pack_catalog یا language_pack_catalog می‌آید.
class DownloadEntry {
  const DownloadEntry({
    required this.id,
    required this.title,
    this.subtitle,
    required this.sizeBytes,
    required this.installed,
    required this.selected,
    required this.progress, // null = در حال دانلود نیست
    this.error,
    this.updateAvailable = false,
    this.flag,
    this.builtIn = false,
  });

  final String id;
  final String title;
  final String? subtitle;
  final int sizeBytes;
  final bool installed;

  /// فعال/انتخاب‌شده (تیک سبز «فعال»، مثل نقشهٔ جاری یا صدای جاری).
  final bool selected;
  final double? progress;
  final String? error;

  /// آیا نسخهٔ جدیدتری روی سرور موجود است (دکمهٔ «آپدیت موجود»).
  final bool updateAvailable;

  /// اموجی پرچم برای آواتار دایره‌ای (کشورها/زبان‌ها).
  final String? flag;

  /// همراه خود اپ (نیاز به دانلود ندارد) — مثل فارسی/انگلیسیِ رابط کاربری.
  final bool builtIn;

  String get sizeLabel {
    final mb = sizeBytes / (1024 * 1024);
    if (mb < 1) return '${(sizeBytes / 1024).round()} KB';
    if (mb < 1024) return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
    return '${(mb / 1024).toStringAsFixed(1)} GB';
  }
}
