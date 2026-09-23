import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/bottom_nav.dart';
import 'legal_screens.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.15,
            colors: [
              AppColors.primaryAccent(context).withOpacity(0.13),
              AppColors.background(context),
            ],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              Column(
                children: [
                  const _SettingsBrandHeader(),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppColors.frameBackground(context)
                            .withOpacity(0.94),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(26)),
                        border: Border(
                          top:
                              BorderSide(color: AppColors.glassBorder(context)),
                        ),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _MenuRow(
                              icon: Icons.palette_rounded,
                              label: AppStrings.literal('تنظیمات ظاهر'),
                              desc: AppStrings.literal(
                                  'رنگ اپ، کارت مسیریابی و ویجت‌های روی نقشه'),
                              iconColor: AppColors.primaryAccent(context),
                              onTap: () => context.push('/appearance-settings'),
                            ),
                            _MenuRow(
                              icon: Icons.alt_route_rounded,
                              label: AppStrings.literal('تنظیمات مسیر'),
                              desc: AppStrings.literal(
                                  'ظاهر مسیر و گزینه‌های مسیریابی'),
                              iconColor: AppColors.primaryAccent(context),
                              onTap: () => context.push('/route-settings'),
                            ),
                            _MenuRow(
                              icon: Icons.videocam_rounded,
                              label: AppStrings.literal('دوربین هوشمند'),
                              desc: AppStrings.literal(
                                  'ضبط ویدیو و دستیار هوشمند رانندگی'),
                              iconColor: const Color(0xFFFF6680),
                              onTap: () => context.push('/dashcam-settings'),
                            ),
                            _MenuRow(
                              icon: Icons.view_in_ar_rounded,
                              label: AppStrings.literal('هد آپ دیسپلی (HUD)'),
                              desc: AppStrings.literal(
                                  'نمایش اطلاعات مسیر روی شیشه جلو'),
                              iconColor: AppColors.primaryAccent(context),
                              onTap: () => context.push('/hud-settings'),
                            ),
                            _MenuRow(
                              icon: Icons.volume_up_rounded,
                              label: AppStrings.literal('تنظیمات صدا'),
                              desc: AppStrings.literal(
                                  'صدا، راهنمای صوتی و بسته‌های صوتی'),
                              iconColor: AppColors.primaryAccent(context),
                              onTap: () => context.push('/voice-settings'),
                            ),
                            _MenuRow(
                              icon: Icons.layers_rounded,
                              label: AppStrings.literal('تنظیمات نقشه'),
                              desc: AppStrings.literal(
                                  'نمایش نقشه، نقاط نمایشی و نقشه‌های آفلاین'),
                              iconColor: const Color(0xFF4EC3E8),
                              onTap: () => context.push('/map-settings'),
                            ),
                            _MenuRow(
                              icon: Icons.navigation_rounded,
                              label: AppStrings.literal('تنظیمات مکان‌نما'),
                              desc: AppStrings.literal(
                                  'خودرو، فلش و ظاهر مکان‌نما روی نقشه'),
                              iconColor: const Color(0xFFB57BFF),
                              onTap: () => context.push('/marker-settings'),
                            ),
                            _MenuRow(
                              icon: Icons.translate_rounded,
                              label: AppStrings.literal('تنظیمات زبان'),
                              desc: AppStrings.literal(
                                  'زبان برنامه و بسته‌های زبان قابل‌دانلود'),
                              iconColor: const Color(0xFF2FA5E6),
                              onTap: () => context.push('/downloads'),
                            ),
                            _MenuRow(
                              icon: Icons.location_on_rounded,
                              label: AppStrings.literal('صفحات مورد علاقه'),
                              desc: AppStrings.literal(
                                  'مکان‌ها و مقصدهای ذخیره‌شده'),
                              iconColor: const Color(0xFF2FA5E6),
                              onTap: () => context.push('/saved-places'),
                            ),
                            _MenuRow(
                              icon: Icons.info_outline_rounded,
                              label: AppStrings.literal('درباره آبتین'),
                              desc: AppStrings.literal(
                                  'اطلاعات برنامه و درباره آبتین‌مپ'),
                              iconColor: const Color(0xFF8B5CF6),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AboutAppScreen(),
                                ),
                              ),
                            ),
                            _MenuRow(
                              icon: Icons.bug_report_rounded,
                              label: AppStrings.literal('گزارش'),
                              desc: AppStrings.literal(
                                  'گزارش POI و مسیریابی آفلاین'),
                              iconColor: const Color(0xFF9CA3AF),
                              onTap: () => context.push('/abm-log'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const BottomNav(currentPage: NavKey.settings),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsBrandHeader extends ConsumerWidget {
  const _SettingsBrandHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 228,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: -194,
            child: Container(
              width: 510,
              height: 510,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: AppColors.primaryAccent(context).withOpacity(0.16)),
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 20,
            child: Text(
              AppStrings.get(context, ref, 'settings_page_title'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 82,
                height: 82,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryAccent(context).withOpacity(0.32),
                      blurRadius: 30,
                      spreadRadius: 3,
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/images/abtinmaps_settings_logo.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => ColoredBox(
                    color: AppColors.primaryAccent(context),
                    child: const Icon(
                      Icons.map_rounded,
                      color: Colors.white,
                      size: 42,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                AppStrings.get(context, ref, 'app_name'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppColors.textPrimary(context),
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 3),
              Text(
                AppStrings.get(context, ref, 'settings_brand_tagline'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary(context),
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.desc,
    required this.iconColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String desc;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.glassPanelSoft(context),
              borderRadius: BorderRadius.circular(15),
              border:
                  Border.all(color: AppColors.glassBorder(context), width: 0.5),
            ),
            child: Row(
              children: [
                Icon(Icons.chevron_left_rounded,
                    color: AppColors.textMuted(context), size: 20),
                const Spacer(),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        AppStrings.literal(label),
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: AppColors.textPrimary(context),
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                      const SizedBox(height: 2),
                      Text(AppStrings.literal(desc),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: AppColors.textSecondary(context))),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
