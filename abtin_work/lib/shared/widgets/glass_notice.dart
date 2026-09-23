import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

OverlayEntry? _activeNotice;
Timer? _noticeTimer;

/// اعلان‌های درون‌برنامه‌ای را موقتاً در بالای صفحه نمایش می‌دهد.
///
/// این پیام‌ها هم‌زمان در مرکز اعلان داخلی ثبت می‌شوند، اما دیگر به دکمهٔ زنگ
/// ثابت یا SnackBar پایین که نقشه و نوار ناوبری را می‌پوشاند وابسته نیستند.
void showGlassNotice(
  BuildContext context,
  String message, {
  required IconData icon,
  required List<Color> colors,
  bool showAboveBottomNav = true,
  Duration duration = const Duration(seconds: 3),
  VoidCallback? onTap,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  _noticeTimer?.cancel();
  _activeNotice?.remove();
  _activeNotice = null;

  late final OverlayEntry entry;
  void dismiss() {
    if (_activeNotice != entry) return;
    _noticeTimer?.cancel();
    _noticeTimer = null;
    entry.remove();
    _activeNotice = null;
  }

  entry = OverlayEntry(
    builder: (overlayContext) {
      final top = MediaQuery.of(overlayContext).padding.top + 12;
      return Positioned(
        top: top,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: onTap == null
                ? null
                : () {
                    dismiss();
                    onTap();
                  },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xE614171F),
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: .14)),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black45,
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: colors,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: colors.last.withValues(alpha: .55),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: Icon(icon, color: Colors.white, size: 16),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          message,
                          style: Theme.of(overlayContext)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                              ),
                        ),
                      ),
                      if (onTap != null)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.chevron_left_rounded,
                            color: Colors.white38,
                            size: 20,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  _activeNotice = entry;
  overlay.insert(entry);
  _noticeTimer = Timer(duration, dismiss);
}
