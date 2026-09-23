import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';

/// هدر مشترک تمام صفحات.
///
/// این ویجت عمداً یک [AppBar] واقعی برمی‌گرداند تا Flutter خودش inset نوار
/// وضعیت و ناچ را مدیریت کند. محتوای داخل AppBar به‌صورت LTR قفل شده است؛
/// بنابراین در زبان فارسی جای دکمه‌ی برگشت و actionها عوض نمی‌شود.
class PageHeader extends StatelessWidget implements PreferredSizeWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.backRoute = '/',
    this.actions,
    this.onRefresh,
  });

  final String title;
  final String? subtitle;
  final String backRoute;
  final List<Widget>? actions;
  final VoidCallback? onRefresh;

  static const double toolbarHeight = 64;
  static const double _toolbarHeightWithSubtitle = 76;

  @override
  Size get preferredSize => Size.fromHeight(
      subtitle == null ? toolbarHeight : _toolbarHeightWithSubtitle);

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primaryAccent(context);
    final border = AppColors.glassBorder(context);
    final height =
        subtitle == null ? toolbarHeight : _toolbarHeightWithSubtitle;
    final trailing = <Widget>[
      if (onRefresh != null)
        _HeaderCircleButton(
          icon: Icons.refresh_rounded,
          color: accent,
          onTap: onRefresh!,
        ),
      ...?actions,
    ];

    return AppBar(
      automaticallyImplyLeading: false,
      primary: true,
      toolbarHeight: height,
      leadingWidth: 0,
      titleSpacing: 0,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      shape: Border(bottom: BorderSide(color: border, width: .6)),
      title: Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: double.infinity,
          height: height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 64),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: AppColors.textPrimary(context),
                              fontWeight: FontWeight.w800,
                              letterSpacing: .2,
                            ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textMuted(context),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: _HeaderCircleButton(
                  icon: Icons.arrow_back_rounded,
                  color: accent,
                  onTap: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go(backRoute);
                    }
                  },
                ),
              ),
              if (trailing.isNotEmpty)
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: trailing
                        .map((widget) => Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: widget,
                            ))
                        .toList(growable: false),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderCircleButton extends StatelessWidget {
  const _HeaderCircleButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.glassPanelSoft(context),
              border: Border.all(color: AppColors.glassBorder(context)),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
        ),
      );
}
