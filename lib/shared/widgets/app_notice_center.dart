import '../../core/localization/app_localizations.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../providers/app_notice_provider.dart';

void showAppNoticeCenter(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _AppNoticeCenterSheet(),
  );
}

class _AppNoticeCenterSheet extends ConsumerStatefulWidget {
  const _AppNoticeCenterSheet();

  @override
  ConsumerState<_AppNoticeCenterSheet> createState() =>
      _AppNoticeCenterSheetState();
}

class _AppNoticeCenterSheetState extends ConsumerState<_AppNoticeCenterSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(appNoticeProvider.notifier).markAllRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final notices = ref.watch(appNoticeProvider);
    final maxHeight = MediaQuery.of(context).size.height * 0.72;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: AppColors.frameBackground(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: AppColors.glassBorder(context)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              color: Colors.white24,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(
              children: [
                const Icon(Icons.notifications_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    AppStrings.literal('اعلان‌های آبتین مپس'),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (notices.isNotEmpty)
                  IconButton(
                    tooltip: AppStrings.literal('پاک کردن همه'),
                    onPressed: () {
                      ref.read(appNoticeProvider.notifier).clear();
                    },
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: Colors.white70),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Expanded(
            child: notices.isEmpty
                ? Center(
                    child: Text(
                      AppStrings.literal('هنوز اعلانی ندارید'),
                      style: TextStyle(color: Colors.white60),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                    itemCount: notices.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 9),
                    itemBuilder: (context, index) {
                      final notice = notices[index];
                      final visual = _noticeVisual(notice.level);
                      final time = TimeOfDay.fromDateTime(notice.createdAt)
                          .format(context);
                      return Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.055),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: visual.color.withValues(alpha: 0.38),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: visual.color.withValues(alpha: 0.18),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(visual.icon,
                                  size: 18, color: visual.color),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          notice.title,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        time,
                                        style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 11),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    notice.message,
                                    style: const TextStyle(
                                        color: Colors.white70, height: 1.35),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

({Color color, IconData icon}) _noticeVisual(AppNoticeLevel level) {
  switch (level) {
    case AppNoticeLevel.success:
      return (color: Colors.greenAccent, icon: Icons.check_circle_rounded);
    case AppNoticeLevel.warning:
      return (color: Colors.amberAccent, icon: Icons.warning_amber_rounded);
    case AppNoticeLevel.error:
      return (color: Colors.redAccent, icon: Icons.error_outline_rounded);
    case AppNoticeLevel.info:
      return (color: Colors.lightBlueAccent, icon: Icons.info_outline_rounded);
  }
}
