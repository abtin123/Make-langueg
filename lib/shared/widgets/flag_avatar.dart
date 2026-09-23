import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// گونهٔ قابِ [FlagAvatar].
///
/// در حالت [circle] خود پرچم با نسبت واقعی ۴:۳ داخل یک جایگاه گرد نمایش داده
/// می‌شود و هیچ بخشی از آن بریده یا کشیده نمی‌شود. در حالت
/// [roundedRectangle] کل پرچم در نسبت رسمی ۴:۳ و با گوشه‌های نرم دیده می‌شود.
enum FlagAvatarStyle { circle, roundedRectangle }

/// کامپوننت واحد نمایش پرچم در کل برنامه.
///
/// برای همهٔ assetهای SVG محلی و emojiهای قدیمی fallback دارد. `size` ارتفاع
/// قاب است؛ عرض در حالت مستطیلی به‌طور پیش‌فرض طبق نسبت رسمی ۴:۳ محاسبه
/// می‌شود. برای موردهای خاص می‌توان `width` یا `height` را صریح تعیین کرد.
class FlagAvatar extends StatelessWidget {
  const FlagAvatar({
    super.key,
    required this.flag,
    this.size = 40,
    this.style = FlagAvatarStyle.circle,
    this.width,
    this.height,
    this.borderRadius,
    this.semanticsLabel,
  });

  /// سازندهٔ کوتاه برای badgeهای فشرده در ردیف‌ها و تنظیمات صوت.
  const FlagAvatar.circle({
    super.key,
    required this.flag,
    this.size = 40,
    this.width,
    this.height,
    this.borderRadius,
    this.semanticsLabel,
  }) : style = FlagAvatarStyle.circle;

  /// سازندهٔ کوتاه برای فهرست زبان‌ها، نقشه‌ها و جایگاه‌هایی که باید خودِ
  /// هندسهٔ کامل پرچم قابل تشخیص باشد.
  const FlagAvatar.rectangle({
    super.key,
    required this.flag,
    this.size = 40,
    this.width,
    this.height,
    this.borderRadius,
    this.semanticsLabel,
  }) : style = FlagAvatarStyle.roundedRectangle;

  /// مسیر asset (ترجیحاً SVG) یا emoji برای داده‌های قدیمی.
  final String flag;

  /// ارتفاع پیش‌فرض قاب.
  final double size;

  final FlagAvatarStyle style;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final String? semanticsLabel;

  bool get _isAsset => flag.trim().startsWith('assets/');
  bool get _isSvg => flag.trim().toLowerCase().endsWith('.svg');

  @override
  Widget build(BuildContext context) {
    final resolvedHeight = height ?? size;
    final resolvedWidth = width ??
        (style == FlagAvatarStyle.circle
            ? resolvedHeight
            : resolvedHeight * 4 / 3);
    final isCircle = style == FlagAvatarStyle.circle;
    final outerRadius = isCircle
        ? BorderRadius.circular(resolvedHeight / 2)
        : (borderRadius ?? BorderRadius.circular(resolvedHeight * 0.18));
    final edgeColor = Colors.black.withValues(alpha: 0.22);

    return Semantics(
      image: true,
      label: semanticsLabel ?? 'پرچم',
      child: SizedBox(
        width: resolvedWidth,
        height: resolvedHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF161B24),
            shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: isCircle ? null : outerRadius,
            border: Border.all(color: edgeColor, width: 0.9),
            boxShadow: const [
              BoxShadow(
                color: Color(0x38000000),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Padding(
            // در badgeهای صوتی خود پرچم باید دایره‌ای دیده شود، نه فقط
            // قاب دور آن. حالت مستطیلی همچنان نسبت رسمی ۴:۳ را حفظ می‌کند.
            padding: isCircle
                ? EdgeInsets.all(resolvedHeight * 0.05)
                : EdgeInsets.zero,
            child: isCircle
                ? ClipOval(
                    child: _isAsset
                        ? _AssetFlag(path: flag.trim(), isSvg: _isSvg)
                        : _EmojiFlag(
                            value: flag,
                            fontSize: resolvedHeight * 0.72,
                          ),
                  )
                : ClipRRect(
                    borderRadius: outerRadius,
                    child: _isAsset
                        ? _AssetFlag(path: flag.trim(), isSvg: _isSvg)
                        : _EmojiFlag(
                            value: flag,
                            fontSize: resolvedHeight * 0.72,
                          ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _AssetFlag extends StatelessWidget {
  const _AssetFlag({required this.path, required this.isSvg});

  final String path;
  final bool isSvg;

  @override
  Widget build(BuildContext context) {
    if (isSvg) {
      return SvgPicture.asset(
        path,
        fit: BoxFit.fill,
        placeholderBuilder: (_) => const _FlagFallback(),
      );
    }
    return Image.asset(
      path,
      fit: BoxFit.fill,
      errorBuilder: (_, __, ___) => const _FlagFallback(),
    );
  }
}

class _EmojiFlag extends StatelessWidget {
  const _EmojiFlag({required this.value, required this.fontSize});

  final String value;
  final double fontSize;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.contain,
        child: Text(value, style: TextStyle(fontSize: fontSize)),
      );
}

class _FlagFallback extends StatelessWidget {
  const _FlagFallback();

  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: Color(0xFF202936),
        child: Center(
          child: Icon(Icons.flag_rounded, color: Colors.white70, size: 20),
        ),
      );
}
