import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/bottom_nav.dart';
import '../../../shared/widgets/flag_avatar.dart';
import '../../../shared/widgets/page_header.dart';
import '../data/voice_pack_catalog.dart';
import 'tts_providers.dart';
import 'voice_pack_providers.dart';

enum _VoiceDownloadTab { downloaded, notDownloaded }

/// تنظیمات صدا؛ همان ساختار صفحهٔ فعلی پروژه حفظ شده و فقط کنترل‌های واقعی
/// صدا/سرعت/اولین هشدار به آن اضافه شده‌اند.
class VoiceSettingsScreen extends ConsumerStatefulWidget {
  const VoiceSettingsScreen({super.key});

  @override
  ConsumerState<VoiceSettingsScreen> createState() =>
      _VoiceSettingsScreenState();
}

class _VoiceSettingsScreenState extends ConsumerState<VoiceSettingsScreen> {
  _VoiceDownloadTab _tab = _VoiceDownloadTab.notDownloaded;

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(ttsServiceProvider);
    final activeVoice = ref.watch(activeVoicePackProvider);
    final installed = ref.watch(installedVoicePacksProvider);
    final manifest =
        ref.watch(voicePackManifestProvider).valueOrNull ?? const [];
    final activePack = _packFor(activeVoice, manifest);
    final displayName = activePack?.title ??
        (activeVoice == null
            ? AppStrings.get(context, ref, 'voice_not_selected')
            : AppStrings.get(context, ref, 'voice_downloaded_label'));

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: PageHeader(
        title: AppStrings.get(context, ref, 'voice_settings'),
        onRefresh: () =>
            ref.read(voicePackCatalogRefreshProvider.notifier).state++,
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
            children: [
              _GuidanceCard(
                title: AppStrings.get(context, ref, 'voice_guidance_title'),
                description: activeVoice == null
                    ? AppStrings.get(
                        context, ref, 'voice_select_from_downloads')
                    : displayName,
                onPlay: activeVoice == null
                    ? null
                    : () => _playAndReport(
                          context,
                          ref,
                          service.playDownloadedSample(activeVoice),
                        ),
                playLabel: AppStrings.get(context, ref, 'play_sample'),
              ),
              const SizedBox(height: 12),
              const _VoiceControlsCard(),
              const SizedBox(height: 12),
              const _FirstAlertCard(),
              const SizedBox(height: 18),
              _VoicePackDownloads(
                manifest: manifest,
                installed: installed,
                active: activeVoice,
                tab: _tab,
                onTabChanged: (value) => setState(() => _tab = value),
              ),
            ],
          ),
          const BottomNav(currentPage: NavKey.voice),
        ],
      ),
    );
  }

  VoicePackRemote? _packFor(String? name, List<VoicePackRemote> manifest) {
    if (name == null) return null;
    for (final pack in manifest) {
      if (pack.name == name) return pack;
    }
    return null;
  }

  Future<void> _playAndReport(
    BuildContext context,
    WidgetRef ref,
    Future<bool> request,
  ) async {
    final played = await request;
    if (!context.mounted || played) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(AppStrings.get(context, ref, 'voice_sample_failed'))),
    );
  }
}

class _GuidanceCard extends StatelessWidget {
  const _GuidanceCard({
    required this.title,
    required this.description,
    required this.onPlay,
    required this.playLabel,
  });

  final String title;
  final String description;
  final VoidCallback? onPlay;
  final String playLabel;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primaryAccent(context);
    final text = AppColors.textPrimary(context);
    final muted = AppColors.textMuted(context);
    return _SettingsCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withOpacity(0.14),
            ),
            child: Icon(Icons.graphic_eq_rounded, color: accent, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: text,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  textAlign: TextAlign.right,
                  style: TextStyle(color: muted, fontSize: 12.5, height: 1.5),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: onPlay,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppColors.glassBorder(context)),
                      backgroundColor: AppColors.surfaceMuted(context),
                      foregroundColor: text,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    icon: Icon(Icons.play_arrow_rounded, color: text, size: 18),
                    label: Text(playLabel),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceControlsCard extends ConsumerWidget {
  const _VoiceControlsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final volume = ref.watch(ttsVolumeProvider);
    final rate = ref.watch(ttsRateProvider);
    final service = ref.read(ttsServiceProvider);
    final text = AppColors.textPrimary(context);
    final muted = AppColors.textSecondary(context);
    final accent = AppColors.primaryAccent(context);

    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SliderRow(
            icon: Icons.volume_up_rounded,
            title: AppStrings.get(context, ref, 'voice_volume'),
            valueLabel: '${(volume * 100).round()}%',
            value: volume.clamp(0.0, 1.0),
            min: 0,
            max: 1,
            divisions: 20,
            onChanged: (value) {
              ref.read(ttsVolumeProvider.notifier).set(value);
              service.setVolume(value);
            },
            textColor: text,
            mutedColor: muted,
            accent: accent,
          ),
          const SizedBox(height: 10),
          _SliderRow(
            icon: Icons.speed_rounded,
            title: AppStrings.get(context, ref, 'voice_speed'),
            valueLabel:
                '${rate.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')}x',
            value: rate.clamp(0.5, 2.0),
            min: 0.5,
            max: 2.0,
            divisions: 6,
            onChanged: (value) {
              ref.read(ttsRateProvider.notifier).set(value);
              service.setPlaybackRate(value);
            },
            textColor: text,
            mutedColor: muted,
            accent: accent,
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.icon,
    required this.title,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.textColor,
    required this.mutedColor,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final Color textColor;
  final Color mutedColor;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, color: accent, size: 21),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              valueLabel,
              style: TextStyle(color: mutedColor, fontSize: 13),
            ),
          ],
        ),
        SliderTheme(
          data: Theme.of(context).sliderTheme.copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _FirstAlertCard extends ConsumerWidget {
  const _FirstAlertCard();

  static const distances = <double>[50, 100, 250, 500, 750, 1000];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref
        .watch(voiceFirstAlertDistanceProvider)
        .clamp(50.0, 1000.0)
        .toDouble();
    final accent = AppColors.primaryAccent(context);
    final text = AppColors.textPrimary(context);
    final muted = AppColors.textMuted(context);

    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withOpacity(0.14),
                ),
                child: Icon(Icons.notifications_active_rounded,
                    color: accent, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      AppStrings.get(context, ref, 'voice_first_alert'),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppStrings.get(context, ref, 'voice_first_alert_desc'),
                      textAlign: TextAlign.right,
                      style:
                          TextStyle(color: muted, fontSize: 11.5, height: 1.45),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final distance in distances)
                ChoiceChip(
                  label: Text(_distanceLabel(context, ref, distance)),
                  selected: (selected - distance).abs() < 0.1,
                  onSelected: (_) => ref
                      .read(voiceFirstAlertDistanceProvider.notifier)
                      .set(distance),
                  selectedColor: accent,
                  labelStyle: TextStyle(
                    color: (selected - distance).abs() < 0.1
                        ? Theme.of(context).colorScheme.onPrimary
                        : text,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                  side: BorderSide(color: AppColors.glassBorder(context)),
                  backgroundColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _distanceLabel(
    BuildContext context,
    WidgetRef ref,
    double value,
  ) {
    final key = value >= 1000
        ? 'distance_alert_1_km'
        : value == 750
            ? 'distance_alert_750_m'
            : value == 500
                ? 'distance_alert_500_m'
                : value == 250
                    ? 'distance_alert_250_m'
                    : value == 100
                        ? 'distance_alert_100_m'
                        : 'distance_alert_50_m';
    return AppStrings.get(context, ref, key);
  }
}

class _VoicePackDownloads extends ConsumerWidget {
  const _VoicePackDownloads({
    required this.manifest,
    required this.installed,
    required this.active,
    required this.tab,
    required this.onTabChanged,
  });

  final List<VoicePackRemote> manifest;
  final Set<String> installed;
  final String? active;
  final _VoiceDownloadTab tab;
  final ValueChanged<_VoiceDownloadTab> onTabChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(voicePackDownloadProgressProvider);
    final errors = ref.watch(voicePackDownloadErrorProvider);
    final accent = AppColors.primaryAccent(context);
    final text = AppColors.textPrimary(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              AppStrings.get(context, ref, 'voice_download_packs'),
              style: TextStyle(
                  color: text, fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(width: 8),
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
              child: const Icon(Icons.download_rounded,
                  color: Colors.white, size: 16),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _VoiceDownloadTabs(
          selected: tab,
          downloadedLabel: AppStrings.get(context, ref, 'downloaded_ones'),
          notDownloadedLabel:
              AppStrings.get(context, ref, 'not_downloaded_ones'),
          onChanged: onTabChanged,
        ),
        const SizedBox(height: 12),
        if (manifest.isEmpty)
          Text(
            AppStrings.get(context, ref, 'voice_list_unavailable'),
            textAlign: TextAlign.right,
            style: TextStyle(color: AppColors.textMuted(context)),
          )
        else
          for (final pack in manifest.where((pack) =>
              tab == _VoiceDownloadTab.downloaded
                  ? installed.contains(pack.name)
                  : !installed.contains(pack.name)))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _VoicePackRow(
                pack: pack,
                installed: installed.contains(pack.name),
                active: active == pack.name,
                progress: progress[pack.name],
                error: errors[pack.name],
              ),
            ),
      ],
    );
  }
}

class _VoiceDownloadTabs extends StatelessWidget {
  const _VoiceDownloadTabs({
    required this.selected,
    required this.downloadedLabel,
    required this.notDownloadedLabel,
    required this.onChanged,
  });

  final _VoiceDownloadTab selected;
  final String downloadedLabel;
  final String notDownloadedLabel;
  final ValueChanged<_VoiceDownloadTab> onChanged;

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
            child: _VoiceTabButton(
              label: downloadedLabel,
              selected: selected == _VoiceDownloadTab.downloaded,
              accent: accent,
              onTap: () => onChanged(_VoiceDownloadTab.downloaded),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _VoiceTabButton(
              label: notDownloadedLabel,
              selected: selected == _VoiceDownloadTab.notDownloaded,
              accent: accent,
              onTap: () => onChanged(_VoiceDownloadTab.notDownloaded),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceTabButton extends StatelessWidget {
  const _VoiceTabButton({
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

class _VoicePackRow extends ConsumerWidget {
  const _VoicePackRow({
    required this.pack,
    required this.installed,
    required this.active,
    required this.progress,
    required this.error,
  });

  final VoicePackRemote pack;
  final bool installed;
  final bool active;
  final double? progress;
  final String? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloading = progress != null;
    final accent = AppColors.primaryAccent(context);
    final text = AppColors.textPrimary(context);
    final muted = AppColors.textMuted(context);
    final genderIsFemale = pack.isFemale;
    final genderLabel = AppStrings.get(
      context,
      ref,
      genderIsFemale ? 'voice_gender_female' : 'voice_gender_male',
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.glassPanel(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.glassBorder(context)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: OutlinedButton(
              onPressed: downloading
                  ? null
                  : () async {
                      if (installed) {
                        await ref
                            .read(activeVoicePackProvider.notifier)
                            .set(pack.name);
                        if (ref.read(alertVoicePackProvider) == null) {
                          await ref
                              .read(alertVoicePackProvider.notifier)
                              .set(pack.name);
                        }
                      } else {
                        await downloadVoicePack(ref, pack);
                      }
                    },
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: accent.withOpacity(0.6)),
                foregroundColor: accent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    downloading
                        ? '${((progress ?? 0) * 100).round()}%'
                        : installed
                            ? (active
                                ? AppStrings.get(context, ref, 'active_label')
                                : AppStrings.get(context, ref, 'select_label'))
                            : AppStrings.get(context, ref, 'download_label'),
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  if (!downloading) ...[
                    const SizedBox(width: 4),
                    Icon(
                      installed
                          ? Icons.check_circle_outline_rounded
                          : Icons.download_rounded,
                      size: 14,
                      color: accent,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (installed && !downloading) ...[
            IconButton(
              tooltip: AppStrings.literal('حذف بسته صوتی'),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: Text(AppStrings.literal('حذف بسته صوتی')),
                    content: Text(AppStrings.literal(
                        'بسته «${pack.shortName}» حذف شود؟')),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: Text(AppStrings.literal('انصراف')),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: Text(AppStrings.literal('حذف')),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await deleteVoicePack(ref, pack);
                }
              },
              icon: Icon(Icons.delete_outline_rounded,
                  color: AppColors.danger, size: 21),
            ),
          ],
          const Spacer(),
          Expanded(
            flex: 2,
            child: Text(
              pack.shortName,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: text, fontWeight: FontWeight.w600, fontSize: 14.5),
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: genderLabel,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: genderIsFemale
                    ? const Color(0xFFFF5FA2).withOpacity(0.16)
                    : const Color(0xFF4AA8FF).withOpacity(0.16),
                border: Border.all(
                  color: genderIsFemale
                      ? const Color(0xFFFF5FA2).withOpacity(0.72)
                      : const Color(0xFF4AA8FF).withOpacity(0.72),
                ),
              ),
              alignment: Alignment.center,
              child: Icon(
                genderIsFemale ? Icons.woman_rounded : Icons.man_rounded,
                color: genderIsFemale
                    ? const Color(0xFFFF73AE)
                    : const Color(0xFF63B7FF),
                size: 21,
              ),
            ),
          ),
          const SizedBox(width: 6),
          FlagAvatar.circle(
            flag: pack.flag,
            size: 34,
            semanticsLabel: 'پرچم ${pack.language}',
          ),
          if (error != null) ...[
            const SizedBox(width: 6),
            Icon(Icons.error_outline_rounded,
                color: Theme.of(context).colorScheme.error, size: 18),
          ],
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.glassPanel(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.glassBorder(context)),
      ),
      child: child,
    );
  }
}
