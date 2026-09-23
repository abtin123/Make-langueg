import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/providers/app_settings_providers.dart';
import '../../shared/widgets/bottom_nav.dart';
import '../../shared/widgets/flag_avatar.dart';
import '../../shared/widgets/page_header.dart';
import '../language_settings/data/language_pack_catalog.dart';
import '../language_settings/data/language_pack_service.dart';
import '../language_settings/presentation/language_pack_providers.dart';
import 'language_hub_providers.dart';

/// صفحهٔ زبان برنامه. فقط فارسی و English داخل APK هستند؛ همهٔ زبان‌های دیگر
/// از manifest ریلیز GitHub به‌صورت بستهٔ ABL دانلود می‌شوند.
class LanguageHubScreen extends ConsumerStatefulWidget {
  const LanguageHubScreen({super.key});

  @override
  ConsumerState<LanguageHubScreen> createState() => _LanguageHubScreenState();
}

enum _LanguageDownloadTab { downloaded, notDownloaded }

class _LanguageHubScreenState extends ConsumerState<LanguageHubScreen> {
  _LanguageDownloadTab _tab = _LanguageDownloadTab.notDownloaded;
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
      () => ref.read(downloadedLanguagesProvider.notifier).loadFromDisk(),
    );
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => AppStrings.get(context, ref, key);
    final activeCode = ref.watch(languageProvider);
    final manifest = ref.watch(languagePackManifestProvider);
    final downloaded = ref.watch(downloadedLanguagesProvider);
    final progress = ref.watch(languageDownloadProgressProvider);
    final errors = ref.watch(languageDownloadErrorProvider);
    // The language list is always visible. fa/en are local packs and remote
    // manifest entries are merged by code so no display gate hides a language.
    final remotePacks =
        manifest.valueOrNull?.toList() ?? const <LanguagePack>[];
    final packsByCode = <String, LanguagePack>{
      for (final pack in builtInLanguages) pack.code: pack,
      for (final pack in remotePacks) pack.code: pack,
    };
    final visibleLanguagePacks = packsByCode.values.toList(growable: false);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: PageHeader(
        title: t('language_program'),
        onRefresh: () =>
            ref.read(languagePackCatalogRefreshProvider.notifier).state++,
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
            children: [
              _DownloadTabs(
                selected: _tab,
                downloadedLabel: t('downloaded_ones'),
                notDownloadedLabel: t('not_downloaded_ones'),
                onChanged: (value) => setState(() => _tab = value),
              ),
              const SizedBox(height: 14),
              if (_tab == _LanguageDownloadTab.downloaded)
                ...visibleLanguagePacks.where((pack) {
                  final bundled =
                      builtInLanguages.any((item) => item.code == pack.code);
                  return bundled || downloaded.contains(pack.code);
                }).map((pack) => _buildLanguageRow(
                      context,
                      ref,
                      t,
                      pack,
                      activeCode,
                      progress,
                      errors,
                      downloaded,
                    ))
              else
                ...visibleLanguagePacks.where((pack) {
                  final bundled =
                      builtInLanguages.any((item) => item.code == pack.code);
                  return !(bundled || downloaded.contains(pack.code));
                }).map((pack) => _buildLanguageRow(
                      context,
                      ref,
                      t,
                      pack,
                      activeCode,
                      progress,
                      errors,
                      downloaded,
                    )),
            ],
          ),
          const BottomNav(currentPage: NavKey.settings),
        ],
      ),
    );
  }
}

Widget _buildLanguageRow(
  BuildContext context,
  WidgetRef ref,
  String Function(String) t,
  LanguagePack pack,
  String activeCode,
  Map<String, LanguageDownloadProgress> progress,
  Map<String, String> errors,
  Set<String> downloaded,
) {
  final isBundled = builtInLanguages.any((item) => item.code == pack.code);
  final isInstalled = isBundled || downloaded.contains(pack.code);
  final isDownloading = progress.containsKey(pack.code);
  return _LanguageRow(
    pack: pack,
    installed: isInstalled,
    selected: isInstalled && activeCode == pack.code,
    progress: progress[pack.code],
    error: errors[pack.code],
    labels: _LanguageRowLabels.fromStrings(t),
    onTap: isDownloading
        ? null
        : () async {
            if (isInstalled) {
              await selectAppLanguage(ref, pack.code);
            } else {
              await downloadLanguagePack(ref, pack);
            }
          },
    onDelete: isBundled || !isInstalled || isDownloading
        ? null
        : () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: Text(t('delete_language_package_title')),
                content: Text(t('delete_language_package_confirm')
                    .replaceAll('{name}', pack.name)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(t('cancel')),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: Text(t('delete_short')),
                  ),
                ],
              ),
            );
            if (confirmed == true) {
              if (activeCode == pack.code) {
                await selectAppLanguage(ref, 'fa');
              }
              await deleteLanguagePack(ref, pack);
            }
          },
  );
}

class _DownloadTabs extends StatelessWidget {
  const _DownloadTabs({
    required this.selected,
    required this.downloadedLabel,
    required this.notDownloadedLabel,
    required this.onChanged,
  });

  final _LanguageDownloadTab selected;
  final String downloadedLabel;
  final String notDownloadedLabel;
  final ValueChanged<_LanguageDownloadTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primaryAccent(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.glassPanelSoft(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.glassBorder(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TabButton(
              label: downloadedLabel,
              selected: selected == _LanguageDownloadTab.downloaded,
              accent: accent,
              onTap: () => onChanged(_LanguageDownloadTab.downloaded),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _TabButton(
              label: notDownloadedLabel,
              selected: selected == _LanguageDownloadTab.notDownloaded,
              accent: accent,
              onTap: () => onChanged(_LanguageDownloadTab.notDownloaded),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? accent.withOpacity(0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected
                  ? AppColors.textPrimary(context)
                  : AppColors.textSecondary(context),
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: TextAlign.right,
        style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13),
      );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard(
      {required this.icon, required this.text, this.loading = false});
  final IconData icon;
  final String text;
  final bool loading;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.glassPanel(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.glassBorder(context)),
        ),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            loading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primaryAccent(context),
                    ),
                  )
                : Icon(icon, color: AppColors.textSecondary(context)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  textAlign: TextAlign.right,
                  style: TextStyle(color: AppColors.textSecondary(context))),
            ),
          ],
        ),
      );
}

/// ردیف زبان دقیقاً مطابق طرح: پرچمِ دایره‌ای سمت راست، نام و زیرنویس در
/// وسط با چینش راست، و یک دکمهٔ دانلود/تیک/درصد در سمت چپ.
class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.pack,
    required this.installed,
    required this.selected,
    required this.onTap,
    required this.labels,
    this.onDelete,
    this.progress,
    this.error,
  });

  final LanguagePack pack;
  final bool installed;
  final bool selected;
  final Future<void> Function()? onTap;
  final Future<void> Function()? onDelete;
  final _LanguageRowLabels labels;
  final LanguageDownloadProgress? progress;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primaryAccent(context);
    final activeProgress = progress;
    final downloading = activeProgress != null;
    final progressValue = activeProgress?.fraction ?? 0;
    final subtitle = error != null
        ? labels.downloadStopped
        : downloading
            ? '${(progressValue * 100).round()}%'
            : installed
                ? labels.installed
                : labels.tapToDownload;
    final hasError = error != null;
    final borderColor = hasError
        ? AppColors.danger
        : selected
            ? accent
            : Colors.white.withOpacity(0.09);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF15161B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: selected ? 1.6 : 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap == null ? null : () => onTap!(),
          borderRadius: BorderRadius.circular(16),
          child: Row(
            children: [
              _LanguageActionButton(
                installed: installed,
                selected: selected,
                downloading: downloading,
                progressValue: progressValue,
              ),
              if (onDelete != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: AppStrings.literal('حذف بسته زبان'),
                  onPressed: () => onDelete!(),
                  icon: Icon(Icons.delete_outline_rounded,
                      color: AppColors.danger, size: 21),
                ),
              ],
              const Spacer(),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      pack.name,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: hasError ? AppColors.danger : Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FlagAvatar.rectangle(
                flag: pack.flag,
                size: 38,
                semanticsLabel: '${AppStrings.literal('پرچم')} ${pack.name}',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// دکمهٔ سمت چپِ ردیف: تیک فقط برای زبان فعال است. زبان نصب‌شده اما
/// غیرفعال با نشان دستگاه نمایش داده می‌شود تا با زبان فعال اشتباه نشود.
class _LanguageActionButton extends StatelessWidget {
  const _LanguageActionButton({
    required this.installed,
    required this.selected,
    required this.downloading,
    required this.progressValue,
  });

  final bool installed;
  final bool selected;
  final bool downloading;
  final double progressValue;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primaryAccent(context);

    if (selected) {
      return Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
        child: const Icon(Icons.check_rounded, color: Colors.white, size: 20),
      );
    }

    if (installed) {
      return Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: accent.withOpacity(0.14),
          border: Border.all(color: accent.withOpacity(0.7), width: 1.25),
        ),
        child: Icon(Icons.phone_android_rounded, color: accent, size: 18),
      );
    }

    if (downloading) {
      return SizedBox(
        width: 34,
        height: 34,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              strokeWidth: 2.2,
              value: progressValue > 0 ? progressValue : null,
              color: accent,
              backgroundColor: accent.withOpacity(0.15),
            ),
            Icon(Icons.download_rounded, color: accent, size: 15),
          ],
        ),
      );
    }

    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: accent, width: 1.3),
      ),
      child: Icon(Icons.file_download_outlined, color: accent, size: 18),
    );
  }
}

class _LanguageRowLabels {
  const _LanguageRowLabels({
    required this.downloadStopped,
    required this.resuming,
    required this.downloading,
    required this.installed,
    required this.tapToDownload,
  });

  final String downloadStopped;
  final String resuming;
  final String downloading;
  final String installed;
  final String tapToDownload;

  factory _LanguageRowLabels.fromStrings(String Function(String) t) =>
      _LanguageRowLabels(
        downloadStopped: t('language_download_stopped'),
        resuming: t('language_resuming'),
        downloading: t('language_downloading'),
        installed: t('language_installed'),
        tapToDownload: t('language_tap_download'),
      );
}
