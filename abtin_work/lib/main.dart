import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/gps/presentation/gps_providers.dart';
import 'shared/providers/app_settings_providers.dart';
import 'features/settings/presentation/appearance_settings_providers.dart';
import 'core/deep_link/deep_link_service.dart';
import 'core/localization/app_localizations.dart';
import 'features/map/presentation/destination_provider.dart';
import 'features/routing/presentation/routing_providers.dart';
import 'features/language_settings/presentation/language_pack_providers.dart';
import 'package:abtin_maps/core/geo/geo_types.dart';
import 'shared/providers/abtinmap_providers.dart';

/// تشخیصی: تا الان وقتی جایی توی build یک صفحه throw می‌شد (provider گم،
/// null، RangeError، هرچی)، در حالت release هیچ چیزی دیده نمی‌شد — فقط یک
/// ناحیه‌ی خالی هم‌رنگ پس‌زمینه (دقیقاً همون چیزی که در صفحات ظاهری/داش‌کم/
/// مسیریابی/خودرو-و-پیکان دیده شد). این سه هوک با هم یعنی هیچ خطایی —
/// چه در build، چه در فریم‌ورک، چه async/zone — بی‌اثر گم نمی‌شود:
///  ۱) ErrorWidget.builder → همان لحظه، دقیقاً همان‌جای صفحه، متن قرمز.
///  ۲) FlutterError.onError → هر خطای فریم‌ورک (نه فقط build) در
///     AbmDebugLog ذخیره و به صفحه‌ی «گزارش» (Settings › گزارش، مسیر
///     /abm-log) اضافه می‌شود؛ یعنی حتی اگر لحظه‌ای رد بشه، بعداً قابل دیدنه.
///  ۳) runZonedGuarded → خطاهایی که اصلاً از مسیر فریم‌ورک رد نمی‌شوند
///     (مثلاً throw داخل یک Future بی‌await) هم گرفته و لاگ می‌شوند.
void _installCrashReporting() {
  ui.PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    
    return true;
  };
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    
    originalOnError?.call(details);
  };

  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Container(
      color: Colors.black,
      alignment: Alignment.topCenter,
      padding: const EdgeInsets.fromLTRB(16, 40, 16, 16),
      child: SingleChildScrollView(
        child: Text(
          details.exceptionAsString(),
          textDirection: TextDirection.ltr,
          style: const TextStyle(
            color: Color(0xFFFF5252),
            fontSize: 12,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  };
}

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    _installCrashReporting();

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );
    runApp(const ProviderScope(child: AbtinApp()));
  }, (error, stack) {
    // خطاهایی که اصلاً وارد سیستم خطای Flutter نمی‌شوند (مثلاً throw توی
    // یک async gap بدون try/catch) اینجا گیر می‌افتند تا اپ کاملاً بی‌صدا
    // کرش نکند و باز هم در همان صفحه‌ی «گزارش» قابل دیدن باشد.
    
  });
}

class AbtinApp extends ConsumerStatefulWidget {
  const AbtinApp({super.key});

  @override
  ConsumerState<AbtinApp> createState() => _AbtinAppState();
}

class _AbtinAppState extends ConsumerState<AbtinApp>
    with WidgetsBindingObserver {
  bool _locationSuspendedForBackground = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final locationService = ref.read(locationServiceProvider);
    final navigationActive = ref.read(activeNavigationProvider) != null;
    if (state == AppLifecycleState.resumed) {
      ref.read(locationLifecycleTickProvider.notifier).state++;
      if (_locationSuspendedForBackground) {
        _locationSuspendedForBackground = false;
        locationService.start();
      }
      return;
    }
    if ((state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden) &&
        !navigationActive) {
      // خارج از ناوبری فعال، نگه‌داشتن GPS، دو سنسور و foreground service در
      // پس‌زمینه مصرف بی‌دلیل CPU/باتری است. شروع مجدد فقط در resumed رخ می‌دهد.
      locationService.stop();
      _locationSuspendedForBackground = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final initAsync = ref.watch(appSettingsInitProvider);

    // بدون این watch، jointKalmanEnabledEffectProvider هیچ‌وقت ساخته نمی‌شود
    // و در نتیجه setJointKalmanEnabled() هرگز صدا زده نمی‌شد — فیلتر کالمن
    // مشترک با وجود پیاده‌سازی کامل، عملاً کال نمی‌شد.
    ref.watch(jointKalmanEnabledEffectProvider);

    // Listen to deep links
    ref.listen(deepLinkDestinationProvider, (previous, next) {
      next.whenData((dest) {
        // مقصدِ دریافتی از اپ‌های دیگر یک درخواست واقعیِ مسیریابی است،
        // نه صرفاً انتخاب پین. بنابراین مستقیماً autoStart می‌شود و صفحه/
        // کارت انتخاب مقصد برای کاربر نمایش داده نمی‌شود.
        ref.read(selectedDestinationProvider.notifier).state =
            SelectedDestination(
          LatLng(dest.lat, dest.lng),
          label: dest.label,
          autoStart: true,
        );
      });
    });

    return initAsync.when(
      data: (_) => _buildApp(context, ref),
      loading: () => const _SplashApp(),
      error: (_, __) => _buildApp(context, ref),
    );
  }

  Widget _buildApp(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final lang = ref.watch(languageProvider);
    AppStrings.setLanguage(lang);
    final primaryColor = ref.watch(primaryColorProvider);
    final appearance = ref.watch(appearanceSettingsProvider);
    final fontColorOverride =
        appearance.appFontColor.alpha == 0 ? null : appearance.appFontColor;
    final fontWeightOverride = appearance.appFontWeightOption.flutterWeight;
    final fontSizeFactor = appearance.appFontSizePercent / 100.0;
    final downloadedLanguageCodes = ref.watch(downloadedLanguagesProvider);
    final supportedLanguageCodes = <String>{
      'fa',
      'en',
      ...downloadedLanguageCodes
    };

    return MaterialApp.router(
      title: AppStrings.get(context, ref, 'app_name'),
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(
        Brightness.light,
        primaryColor,
        fontColorOverride: fontColorOverride,
        fontWeightOverride: fontWeightOverride,
        fontSizeFactor: 1.0,
        fontFamily: appearance.appFontFamily.flutterFamily,
      ),
      darkTheme: AppTheme.build(
        Brightness.dark,
        primaryColor,
        fontColorOverride: fontColorOverride,
        fontWeightOverride: fontWeightOverride,
        fontSizeFactor: 1.0,
        fontFamily: appearance.appFontFamily.flutterFamily,
      ),
      themeMode: themeMode,
      routerConfig: appRouter,
      locale: Locale(lang),
      supportedLocales: [
        for (final code in supportedLanguageCodes) Locale(code),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final overlayStyle = SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness:
              isDark ? Brightness.light : Brightness.dark,
          systemNavigationBarDividerColor: Colors.transparent,
        );
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlayStyle,
          child: MediaQuery(
            // هم مقیاس فونت سیستم و هم ضریب انتخاب‌شده در تنظیمات اپ را
            // روی تمام Textها اعمال می‌کنیم؛ این کار TextStyleهای صریح را
            // هم پوشش می‌دهد.
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(
                (MediaQuery.of(context)
                            .textScaler
                            .clamp(minScaleFactor: 0.85, maxScaleFactor: 1.15)
                            .scale(1.0) *
                        fontSizeFactor)
                    .clamp(0.75, 1.5),
              ),
            ),
            child: Directionality(
              textDirection: const {'fa', 'ar', 'he', 'ur'}.contains(lang)
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }
}

/// Minimal splash shown only for the brief moment it takes to read the
/// persisted language/theme from the local database on cold start.
class _SplashApp extends StatelessWidget {
  const _SplashApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Color(0xFF0A0D12),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF2FE6C4)),
        ),
      ),
    );
  }
}
