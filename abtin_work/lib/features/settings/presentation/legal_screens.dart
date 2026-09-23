import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/bottom_nav.dart';
import '../../../shared/widgets/page_header.dart';

class PrivacyPolicyScreen extends ConsumerWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: PageHeader(
          title: AppStrings.get(context, ref, 'privacy_policy_title')),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 112),
            child: Text(
              AppStrings.get(context, ref, 'privacy_policy_body'),
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.textSecondary(context),
                    height: 1.8,
                  ),
            ),
          ),
          const BottomNav(currentPage: NavKey.settings),
        ],
      ),
    );
  }
}

class AboutAppScreen extends ConsumerWidget {
  const AboutAppScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: PageHeader(
          title: AppStrings.get(context, ref, 'about_abtin_maps_title')),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 128),
              child: Column(
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryAccent(context)
                              .withOpacity(0.24),
                          blurRadius: 28,
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/images/abtinmaps_settings_logo.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    AppStrings.get(context, ref, 'app_name'),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: AppColors.textPrimary(context),
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppStrings.get(context, ref, 'version_label'),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.textSecondary(context)),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    AppStrings.get(context, ref, 'app_tagline'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary(context),
                          height: 1.6,
                        ),
                  ),
                  const SizedBox(height: 28),
                  _AboutCard(
                    icon: Icons.support_agent_rounded,
                    iconColor: AppColors.primaryAccent(context),
                    title: AppStrings.get(context, ref, 'about_support'),
                    lines: const [
                      'abtinmaps@gmail.com',
                      'alimohammad1238@gmail.com'
                    ],
                    emailLines: true,
                  ),
                  const SizedBox(height: 12),
                  _AboutCard(
                    icon: Icons.auto_awesome_rounded,
                    iconColor: const Color(0xFF9B87F5),
                    title: AppStrings.get(context, ref, 'about_creators'),
                    lines: AppStrings.get(context, ref, 'about_creator_names')
                        .split('\n'),
                  ),
                ],
              ),
            ),
            const BottomNav(currentPage: NavKey.settings),
          ],
        ),
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.lines,
    this.emailLines = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final List<String> lines;
  final bool emailLines;

  Future<void> _composeEmail(BuildContext context, String email) async {
    final opened = await launchUrl(
      Uri(scheme: 'mailto', path: email),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppStrings.literal(
                'برنامهٔ ایمیل برای ارسال پیام در دسترس نیست.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.glassPanelSoft(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.glassBorder(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: iconColor.withOpacity(0.13),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.textPrimary(context),
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: emailLines
                        ? InkWell(
                            onTap: () => _composeEmail(context, line),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Icon(Icons.mail_outline_rounded,
                                      size: 16,
                                      color: AppColors.primaryAccent(context)),
                                  const SizedBox(width: 6),
                                  Text(
                                    line,
                                    textDirection: TextDirection.ltr,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color:
                                              AppColors.primaryAccent(context),
                                          decoration: TextDecoration.underline,
                                          decorationColor:
                                              AppColors.primaryAccent(context),
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Text(line,
                            textAlign: TextAlign.right,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: AppColors.textSecondary(context))),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
