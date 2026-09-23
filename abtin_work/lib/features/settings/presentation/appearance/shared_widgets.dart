import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/appearance_settings.dart' show RouteLineStyle;

class PillChoice extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const PillChoice({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          height: 36,
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(colors: [
                    AppColors.primaryAccentLight(context),
                    AppColors.primaryAccent(context),
                  ])
                : null,
            color: selected ? null : AppColors.surfaceMuted(context),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: selected
                        ? Colors.white
                        : AppColors.textSecondary(context),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: selected
                              ? Colors.white
                              : AppColors.textPrimary(context),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TabRadio extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const TabRadio({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          height: 34,
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(colors: [
                    AppColors.primaryAccentLight(context),
                    AppColors.primaryAccent(context),
                  ])
                : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected
                        ? Colors.white
                        : AppColors.textSecondary(context),
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class CardHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const CardHeader({required this.title, required this.icon});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.start,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary(context),
                ),
          ),
        ),
        Icon(icon, color: AppColors.textMuted(context), size: 18),
      ],
    );
  }
}

class RowDivider extends StatelessWidget {
  const RowDivider();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 10),
      color: AppColors.textMuted(context).withOpacity(0.12),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppColors.textSecondary(context),
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

/// نکته: عمداً «AppColorSwatch» نامیده شده، نه «ColorSwatch» — چون
/// flutter/material.dart از قبل یک `ColorSwatch<T>` دارد و هم‌نام بودن
/// باعث تداخل ایمپورت (ambiguous import) در فایل‌هایی می‌شود که هر دو
/// را وارد می‌کنند.
class AppColorSwatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const AppColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final dark = color.computeLuminance() < 0.45;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Ink(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? AppColors.primaryAccent(context)
                  : (dark
                      ? Colors.transparent
                      : Colors.black.withOpacity(0.13)),
              width: selected ? 2.5 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.primaryAccent(context).withOpacity(0.3),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: selected
              ? Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: color.computeLuminance() > 0.6
                      ? Colors.black
                      : Colors.white,
                )
              : null,
        ),
      ),
    );
  }
}

/// دکمه‌ی «رنگ سفارشی» — یک چرخ رنگین‌کمانی که با تپ، پالتِ کاملِ
/// [ColorPickerSheet] را باز می‌کند (نه یک رنگ ثابتِ از پیش تعیین‌شده).
class RainbowSwatch extends StatelessWidget {
  final VoidCallback onTap;
  final bool selected;
  const RainbowSwatch({required this.onTap, this.selected = false});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Ink(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const SweepGradient(colors: [
              Color(0xFFFF5555),
              Color(0xFFFFC44D),
              Color(0xFF55E555),
              Color(0xFF55C4FF),
              Color(0xFF8A3FD0),
              Color(0xFFFF55C4),
              Color(0xFFFF5555),
            ]),
            border: Border.all(
              color: selected
                  ? AppColors.primaryAccent(context)
                  : Colors.black.withOpacity(0.13),
              width: selected ? 2.5 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.primaryAccent(context).withOpacity(0.3),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: selected
              ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

class ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  const ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return Opacity(
      opacity: enabled ? 1 : 0.52,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary(context).withOpacity(0.85),
                  ),
            ),
          ),
          SizedBox(
            width: 44,
            height: 24,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: enabled ? () => onChanged!(!value) : null,
                customBorder: const StadiumBorder(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: value
                        ? LinearGradient(colors: [
                            AppColors.primaryAccentLight(context),
                            AppColors.primaryAccent(context),
                          ])
                        : null,
                    // قبلاً این پس‌زمینه یک سفیدِ تقریباً‌شفاف (۸٪) بود که در
                    // تمِ روشن روی پنلِ خودش تقریباً نامرئی می‌شد و دکمه‌ی
                    // خاموش کاملاً سفید به نظر می‌رسید. حالا از همان طیفِ
                    // خاکستریِ معنایی (textMuted) استفاده می‌شود که مستقل از
                    // تیره/روشن بودن تم، همیشه قابل تشخیص است.
                    color: value
                        ? null
                        : AppColors.textMuted(context).withOpacity(0.22),
                  ),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 180),
                    alignment: value
                        ? AlignmentDirectional.centerStart
                        : AlignmentDirectional.centerEnd,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.25),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ردیفِ مقدار عددی با دکمه‌های +/- به‌جای اسلایدر — طبق درخواستِ کاربر،
/// همه‌ی «بزرگ/کوچک‌شدن»‌ها (عرض جاده، اندازه‌ی پیکان، شدت گلو، زاویه‌ی
/// تیلت) باید با استپر باشند، نه کشیدنِ یک thumb روی خط.
class StepperValueRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double>? onChanged;
  final String Function(double) valueBuilder;
  const StepperValueRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
    required this.valueBuilder,
  });
  @override
  Widget build(BuildContext context) {
    final v = value.clamp(min, max);
    final enabled = onChanged != null;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary(context),
                ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.glassBorder(context)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StepperBtn(
                icon: Icons.remove_rounded,
                onTap: (enabled && v > min)
                    ? () => onChanged!((v - step).clamp(min, max))
                    : null,
              ),
              SizedBox(
                width: 54,
                child: Text(
                  valueBuilder(v),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: enabled
                            ? AppColors.textPrimary(context)
                            : AppColors.textMuted(context),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              StepperBtn(
                icon: Icons.add_rounded,
                onTap: (enabled && v < max)
                    ? () => onChanged!((v + step).clamp(min, max))
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class StepperRow extends ConsumerWidget {
  final String label;
  final Color swatchColor;
  final int value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  const StepperRow({
    required this.label,
    required this.swatchColor,
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: swatchColor,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.glassBorder(context)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StepperBtn(icon: Icons.remove_rounded, onTap: onMinus),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  value.toString(),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary(context),
                      ),
                ),
              ),
              StepperBtn(icon: Icons.add_rounded, onTap: onPlus),
            ],
          ),
        ),
      ],
    );
  }
}

class StepperBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const StepperBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return SizedBox(
      width: 24,
      height: 24,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Icon(
              icon,
              size: 14,
              color: enabled
                  ? AppColors.textSecondary(context)
                  : AppColors.textMuted(context).withOpacity(0.35),
            ),
          ),
        ),
      ),
    );
  }
}

class ReadonlyRow extends StatelessWidget {
  final String label;
  final Color swatchColor;
  const ReadonlyRow({required this.label, required this.swatchColor});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: swatchColor,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        Icon(Icons.chevron_left_rounded,
            color: AppColors.textMuted(context), size: 18),
      ],
    );
  }
}

class ViewModeCard extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget preview;
  const ViewModeCard({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.preview,
  });
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.background(context).withOpacity(0.55),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? AppColors.primaryAccent(context)
                  : AppColors.glassBorder(context),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            children: [
              preview,
              const SizedBox(height: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: selected
                          ? AppColors.primaryAccent(context)
                          : AppColors.textPrimary(context),
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 18,
                child: selected
                    ? Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: AppColors.primaryAccent(context),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check_rounded,
                              color: Colors.white, size: 12),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RouteLineStyleChip extends StatelessWidget {
  final String label;
  final RouteLineStyle style;
  final bool selected;
  final VoidCallback onTap;
  const RouteLineStyleChip({
    required this.label,
    required this.style,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(colors: [
                    AppColors.primaryAccentLight(context),
                    AppColors.primaryAccent(context),
                  ])
                : null,
            color: selected ? null : AppColors.surfaceMuted(context),
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : AppColors.glassBorder(context),
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 8,
                child: CustomPaint(
                  painter: RouteLinePreviewPainter(style: style),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: selected
                          ? Colors.white
                          : AppColors.textPrimary(context),
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RouteLinePreviewPainter extends CustomPainter {
  final RouteLineStyle style;
  const RouteLinePreviewPainter({required this.style});
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFF8A3FD0)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final dotPaint = Paint()..color = const Color(0xFF8A3FD0);
    switch (style) {
      case RouteLineStyle.solid:
        canvas.drawLine(Offset(0, size.height / 2),
            Offset(size.width, size.height / 2), linePaint);
        break;
      case RouteLineStyle.dotted:
        double x = 0;
        while (x < size.width) {
          canvas.drawCircle(Offset(x, size.height / 2), 1.6, dotPaint);
          x += 5;
        }
        break;
      case RouteLineStyle.dashed:
        double x = 0;
        while (x < size.width) {
          canvas.drawLine(Offset(x, size.height / 2),
              Offset(x + 4, size.height / 2), linePaint);
          x += 8;
        }
        break;
      case RouteLineStyle.dotDash:
        double x = 0;
        while (x < size.width) {
          canvas.drawCircle(Offset(x, size.height / 2), 1.6, dotPaint);
          x += 3;
          if (x < size.width) {
            canvas.drawLine(Offset(x, size.height / 2),
                Offset(x + 4, size.height / 2), linePaint);
            x += 7;
          }
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant RouteLinePreviewPainter old) =>
      old.style != style;
}

class TwoDIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      size.width * 0.08,
      size.height * 0.18,
      size.width * 0.84,
      size.height * 0.64,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()..color = const Color(0xFF1C2733),
    );
    final grid = Paint()
      ..color = const Color(0xFF33404F)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(rect.left, rect.top + rect.height * 0.5),
      Offset(rect.right, rect.top + rect.height * 0.5),
      grid,
    );
    canvas.drawLine(
      Offset(rect.left + rect.width * 0.38, rect.top),
      Offset(rect.left + rect.width * 0.38, rect.bottom),
      grid,
    );
  }

  @override
  bool shouldRepaint(covariant TwoDIconPainter old) => false;
}

class ThreeDIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    _drawTrapezoid(canvas, size.width * 0.10, size.height * 0.85,
        size.width * 0.18, size.height * 0.55, const Color(0xFF3A2C4D));
    _drawTrapezoid(canvas, size.width * 0.30, size.height * 0.85,
        size.width * 0.20, size.height * 0.35, const Color(0xFF4A3966));
    _drawTrapezoid(canvas, size.width * 0.52, size.height * 0.85,
        size.width * 0.16, size.height * 0.60, const Color(0xFF3A2C4D));
    _drawTrapezoid(canvas, size.width * 0.70, size.height * 0.85,
        size.width * 0.22, size.height * 0.30, const Color(0xFF59457A));
  }

  void _drawTrapezoid(
      Canvas canvas, double x, double baseY, double w, double h, Color color) {
    final p = Path()
      ..moveTo(x, baseY)
      ..lineTo(x + w, baseY)
      ..lineTo(x + w * 0.85, baseY - h)
      ..lineTo(x + w * 0.15, baseY - h)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant ThreeDIconPainter old) => false;
}

/// یک [Color] را به رشته‌ی هگزِ `#RRGGBB` تبدیل می‌کند (بدون آلفا) — طرفِ
/// تبدیل هگز به رنگ برای کنترل‌های ظاهری مشترک.
String _colorToHex(Color c) {
  return '#${(c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// شیت انتخاب‌گرِ کاملِ رنگ (HSV): مربعِ اشباع/روشنایی + نوارِ رنگ + فیلدِ
/// هگز. جایگزینِ لیستِ چندتا رنگِ پیش‌فرض — کاربر می‌تواند هر رنگی را
/// انتخاب کند، نه فقط از میان چند سواچ ثابت.
class ColorPickerSheet extends ConsumerStatefulWidget {
  const ColorPickerSheet({required this.initial});
  final Color initial;

  static Future<Color?> show(BuildContext context, Color initial) {
    return showModalBottomSheet<Color>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ColorPickerSheet(initial: initial),
    );
  }

  @override
  ConsumerState<ColorPickerSheet> createState() => ColorPickerSheetState();
}

class ColorPickerSheetState extends ConsumerState<ColorPickerSheet> {
  late HSVColor _hsv;
  late final TextEditingController _hexCtrl;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
    _hexCtrl = TextEditingController(text: _colorToHex(widget.initial));
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  void _apply(HSVColor next) {
    setState(() {
      _hsv = next;
      _hexCtrl.text = _colorToHex(next.toColor());
    });
  }

  void _applyHexInput(String v) {
    var h = v.trim().replaceFirst('#', '');
    if (h.length == 3) h = h.split('').map((c) => c + c).join('');
    if (h.length != 6) return;
    final val = int.tryParse(h, radix: 16);
    if (val == null) return;
    setState(() => _hsv = HSVColor.fromColor(Color(0xFF000000 | val)));
  }

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: AppColors.glassBorder(context)),
      ),
      padding: EdgeInsets.fromLTRB(
          18, 12, 18, 18 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textMuted(context).withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SVSquare(
            hue: _hsv.hue,
            saturation: _hsv.saturation,
            value: _hsv.value,
            onChanged: (s, v) => _apply(_hsv.withSaturation(s).withValue(v)),
          ),
          const SizedBox(height: 16),
          HueSlider(
            hue: _hsv.hue,
            onChanged: (h) => _apply(_hsv.withHue(h)),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(0.25)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _hexCtrl,
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    filled: true,
                    fillColor: AppColors.surfaceMuted(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: _applyHexInput,
                  onEditingComplete: () => _applyHexInput(_hexCtrl.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryAccent(context),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(color),
              child: Text(
                AppStrings.get(context, ref, 'confirm'),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// مربعِ اشباع×روشناییِ HSV — محورِ افقی = saturation، محورِ عمودی (از
/// پایین به بالا) = value.
class SVSquare extends StatelessWidget {
  const SVSquare({
    required this.hue,
    required this.saturation,
    required this.value,
    required this.onChanged,
  });
  final double hue;
  final double saturation;
  final double value;
  final void Function(double saturation, double value) onChanged;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.6,
      child: LayoutBuilder(
        builder: (context, constraints) {
          void handle(Offset local) {
            final s = (local.dx / constraints.maxWidth).clamp(0.0, 1.0);
            final v = 1.0 - (local.dy / constraints.maxHeight).clamp(0.0, 1.0);
            onChanged(s, v);
          }

          return GestureDetector(
            onPanDown: (d) => handle(d.localPosition),
            onPanUpdate: (d) => handle(d.localPosition),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white,
                            HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: saturation * constraints.maxWidth - 10,
                    top: (1 - value) * constraints.maxHeight - 10,
                    child: IgnorePointer(
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.45),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// نوارِ افقیِ طیفِ رنگین‌کمانی برای انتخابِ Hue (۰ تا ۳۶۰ درجه).
class HueSlider extends StatelessWidget {
  const HueSlider({required this.hue, required this.onChanged});
  final double hue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        void handle(Offset local) {
          final h = (local.dx / constraints.maxWidth).clamp(0.0, 1.0) * 360.0;
          onChanged(h.clamp(0.0, 359.9));
        }

        return GestureDetector(
          onPanDown: (d) => handle(d.localPosition),
          onPanUpdate: (d) => handle(d.localPosition),
          child: Container(
            height: 30,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: const LinearGradient(colors: [
                Color(0xFFFF0000),
                Color(0xFFFFFF00),
                Color(0xFF00FF00),
                Color(0xFF00FFFF),
                Color(0xFF0000FF),
                Color(0xFFFF00FF),
                Color(0xFFFF0000),
              ]),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: (hue / 360.0) * constraints.maxWidth - 3,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Container(
                      width: 6,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.35),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
