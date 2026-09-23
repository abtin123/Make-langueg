import 'package:flutter/material.dart';

import 'app_colors.dart';
import '../../shared/widgets/gradient_slider_track_shape.dart';

/// سازندهٔ تم برنامه.
///
/// هر دو تم با یک رنگ تأکیدی مشترک ساخته می‌شوند؛ بنابراین هر تغییر در
/// [primaryColorProvider] بدون نیاز به بازسازی دستی ویجت‌ها در MaterialApp
/// و تمام کامپوننت‌های وابسته به ColorScheme اعمال می‌شود.
class AppTheme {
  AppTheme._();

  static TextTheme _buildTextTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final primaryText = isDark ? Colors.white : const Color(0xFF17212B);
    final secondaryText =
        isDark ? const Color(0xFFB9C1CD) : const Color(0xFF52606D);

    return TextTheme(
      displayLarge: TextStyle(
          color: primaryText, fontSize: 32, fontWeight: FontWeight.bold),
      displayMedium: TextStyle(
          color: primaryText, fontSize: 28, fontWeight: FontWeight.bold),
      displaySmall: TextStyle(
          color: primaryText, fontSize: 24, fontWeight: FontWeight.bold),
      headlineLarge: TextStyle(
          color: primaryText, fontSize: 22, fontWeight: FontWeight.w700),
      headlineMedium: TextStyle(
          color: primaryText, fontSize: 20, fontWeight: FontWeight.w600),
      headlineSmall: TextStyle(
          color: primaryText, fontSize: 18, fontWeight: FontWeight.w600),
      titleLarge: TextStyle(
          color: primaryText, fontSize: 17, fontWeight: FontWeight.bold),
      titleMedium: TextStyle(
          color: primaryText, fontSize: 16, fontWeight: FontWeight.w600),
      titleSmall: TextStyle(
          color: primaryText, fontSize: 14, fontWeight: FontWeight.w500),
      bodyLarge: TextStyle(color: primaryText, fontSize: 16),
      bodyMedium: TextStyle(color: primaryText, fontSize: 14),
      bodySmall: TextStyle(color: secondaryText, fontSize: 12),
      labelLarge: TextStyle(
          color: primaryText, fontSize: 14, fontWeight: FontWeight.bold),
      labelMedium: TextStyle(color: secondaryText, fontSize: 12),
      labelSmall: TextStyle(color: secondaryText, fontSize: 10),
    );
  }

  /// اعمالِ اوراردایِ اختیاریِ رنگ/ضخامت/اندازهٔ فونت روی یک [TextTheme].
  /// هر پارامترِ null یا ۱.۰ یعنی «بدون تغییر» — با مقادیرِ پیش‌فرض،
  /// خروجی دقیقاً همان [base] است و ظاهرِ فعلی تغییر نمی‌کند.
  static TextTheme _applyFontOverrides(
    TextTheme base, {
    Color? color,
    FontWeight? weight,
    double fontSizeFactor = 1.0,
  }) {
    TextStyle? map(TextStyle? style) {
      if (style == null) return style;
      return style.copyWith(
        color: color ?? style.color,
        fontWeight: weight ?? style.fontWeight,
        fontSize:
            style.fontSize == null ? null : style.fontSize! * fontSizeFactor,
      );
    }

    return base.copyWith(
      displayLarge: map(base.displayLarge),
      displayMedium: map(base.displayMedium),
      displaySmall: map(base.displaySmall),
      headlineLarge: map(base.headlineLarge),
      headlineMedium: map(base.headlineMedium),
      headlineSmall: map(base.headlineSmall),
      titleLarge: map(base.titleLarge),
      titleMedium: map(base.titleMedium),
      titleSmall: map(base.titleSmall),
      bodyLarge: map(base.bodyLarge),
      bodyMedium: map(base.bodyMedium),
      bodySmall: map(base.bodySmall),
      labelLarge: map(base.labelLarge),
      labelMedium: map(base.labelMedium),
      labelSmall: map(base.labelSmall),
    );
  }

  static ThemeData build(
    Brightness brightness,
    Color primaryColor, {
    Color? fontColorOverride,
    FontWeight? fontWeightOverride,
    double fontSizeFactor = 1.0,
    String? fontFamily,
  }) {
    final isDark = brightness == Brightness.dark;
    final scaffold = isDark ? const Color(0xFF0A0D12) : const Color(0xFFF6F8FC);
    final surface = isDark ? const Color(0xFF11161D) : Colors.white;
    final onSurface =
        isDark ? const Color(0xFFF4F7FB) : const Color(0xFF17212B);
    final onSurfaceVariant =
        isDark ? const Color(0xFFBAC3D0) : const Color(0xFF5E6B78);
    final primaryOnColor =
        primaryColor.computeLuminance() > 0.43 ? Colors.black : Colors.white;

    final seededScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: brightness,
    );
    final scheme = seededScheme.copyWith(
      primary: primaryColor,
      onPrimary: primaryOnColor,
      secondary: primaryColor,
      onSecondary: primaryOnColor,
      surface: surface,
      onSurface: onSurface,
      onSurfaceVariant: onSurfaceVariant,
      outline: isDark ? const Color(0xFF617083) : const Color(0xFF7C8998),
      surfaceTint: Colors.transparent,
    );
    final textTheme = _applyFontOverrides(
      _buildTextTheme(brightness),
      color: fontColorOverride,
      weight: fontWeightOverride,
      fontSizeFactor: fontSizeFactor,
    );
    final outlineBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: scheme.outline.withOpacity(0.35)),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontFamily ?? 'Vazirmatn',
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      canvasColor: scaffold,
      dividerColor: scheme.outline.withOpacity(0.24),
      splashFactory: InkSparkle.splashFactory,
      textTheme: textTheme,
      primaryTextTheme: textTheme.apply(
          bodyColor: scheme.onPrimary, displayColor: scheme.onPrimary),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: onSurface,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: onSurface),
      ),
      iconTheme: IconThemeData(color: onSurfaceVariant),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? Color.lerp(surface, Colors.white, 0.045)
            : Color.lerp(surface, Colors.black, 0.02),
        hintStyle: TextStyle(color: onSurfaceVariant.withOpacity(0.8)),
        labelStyle: TextStyle(color: onSurfaceVariant),
        enabledBorder: outlineBorder,
        focusedBorder: outlineBorder.copyWith(
          borderSide: BorderSide(color: primaryColor, width: 1.6),
        ),
        errorBorder: outlineBorder.copyWith(
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: outlineBorder.copyWith(
          borderSide: BorderSide(color: scheme.error, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: primaryOnColor,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: BorderSide(color: primaryColor.withOpacity(0.7)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primaryColor),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: primaryOnColor,
        shape: const CircleBorder(),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primaryOnColor
              : scheme.outline,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primaryColor
              : scheme.outline.withOpacity(0.38),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primaryColor,
        inactiveTrackColor: primaryColor.withOpacity(isDark ? 0.20 : 0.16),
        thumbColor: Colors.white,
        overlayColor: primaryColor.withOpacity(0.16),
        trackHeight: 5,
        trackShape: GradientSliderTrackShape(
          gradient: LinearGradient(
            colors: [
              Color.lerp(primaryColor, const Color(0xFF2FE6C4), 0.45)!,
              primaryColor,
              Color.lerp(primaryColor, const Color(0xFF8A3FD0), 0.40)!,
            ],
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primaryColor),
      snackBarTheme: SnackBarThemeData(
        backgroundColor:
            isDark ? const Color(0xFF252C35) : const Color(0xFF27313D),
        contentTextStyle:
            const TextStyle(color: Colors.white, fontFamily: 'Vazirmatn'),
        actionTextColor: primaryColor,
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primaryColor.withOpacity(0.16),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? primaryColor
                : onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? primaryColor
                : onSurfaceVariant,
            fontFamily: fontFamily ?? 'Vazirmatn',
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark
            ? Color.lerp(surface, Colors.white, 0.055)!
            : Color.lerp(surface, Colors.black, 0.04)!,
        selectedColor: primaryColor.withOpacity(0.16),
        secondarySelectedColor: primaryColor.withOpacity(0.16),
        labelStyle: textTheme.labelMedium!,
        secondaryLabelStyle:
            textTheme.labelMedium!.copyWith(color: primaryColor),
        side: BorderSide(color: scheme.outline.withOpacity(0.32)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  static ThemeData get dark => build(Brightness.dark, const Color(0xFF2FE6C4));
  static ThemeData get light =>
      build(Brightness.light, const Color(0xFF2FE6C4));
}
