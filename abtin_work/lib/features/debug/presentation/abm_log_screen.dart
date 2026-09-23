import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/abm_debug_log.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/providers/share_service.dart';
import '../../../shared/widgets/bottom_nav.dart';
import '../../../shared/widgets/page_header.dart';

class AbmLogScreen extends StatefulWidget {
  const AbmLogScreen({super.key});

  @override
  State<AbmLogScreen> createState() => _AbmLogScreenState();
}

class _AbmLogScreenState extends State<AbmLogScreen> {
  Future<void> _copyAll(BuildContext context) async {
    final logs = AbmDebugLog.logs;
    if (logs.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: logs.join('\n')));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('گزارش POI و مسیریابی کپی شد.')),
    );
  }

  Future<void> _shareAll(BuildContext context) async {
    final logs = AbmDebugLog.logs;
    if (logs.isEmpty) return;
    await ShareService().share(
      logs.join('\n'),
      subject: 'AbtinMaps - Offline POI & Routing Debug',
    );
  }

  @override
  Widget build(BuildContext context) {
    final logs = AbmDebugLog.logs;
    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: PageHeader(
        title: 'گزارش POI و مسیریابی آفلاین',
        backRoute: '/settings',
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            tooltip: 'ارسال گزارش',
            onPressed: logs.isEmpty ? null : () => _shareAll(context),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: 'کپی همه',
            onPressed: logs.isEmpty ? null : () => _copyAll(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'پاک‌کردن',
            onPressed: logs.isEmpty ? null : () => setState(AbmDebugLog.clear),
          ),
        ],
      ),
      body: Stack(
        children: [
          logs.isEmpty
              ? const Center(
                  child: Text(
                    'هنوز لاگ POI یا مسیریابی ثبت نشده است.\nیک جستجوی آفلاین یا محاسبه مسیر انجام دهید.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 112),
                  itemCount: logs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final line = logs[i];
                    final isError = RegExp(
                      r'ERROR|FAILED|FAIL|EXCEPTION|NO_ROUTE|ناموفق|خطا',
                      caseSensitive: false,
                    ).hasMatch(line);
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isError ? const Color(0x33EB5757) : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isError ? const Color(0x66EB5757) : Colors.white.withOpacity(0.08),
                        ),
                      ),
                      child: SelectableText(
                        line,
                        style: TextStyle(
                          color: isError ? const Color(0xFFFF8A8A) : Colors.white70,
                          fontSize: 12.5,
                          fontFamily: 'monospace',
                          height: 1.4,
                        ),
                      ),
                    );
                  },
                ),
          const BottomNav(currentPage: NavKey.settings),
        ],
      ),
    );
  }
}
