import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'core/bootstrap.dart';
import 'core/constants/app_constants.dart';
import 'core/di/injection.dart';
import 'core/localization/app_localization.dart';
import 'core/localization/locale_keys.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/models/app_settings.dart';
import 'features/settings/cubit/settings_cubit.dart';
import 'features/settings/cubit/settings_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Awaited, unlike the rest: the splash renders the wordmark out of the
  // translation bundles, so they have to be loaded before the first frame.
  // Two small JSON reads from the bundle — not the slow part of startup.
  await EasyLocalization.ensureInitialized();

  // Started and deliberately NOT awaited. Hive's boxes and the service locator
  // now come up while the splash animates, instead of the launch waiting on
  // them with nothing on screen. The splash finishes on whichever of the two
  // takes longer — see SplashScreen.
  unawaited(AppBootstrap.future);

  runApp(
    EasyLocalization(
      supportedLocales: AppLocalization.supportedLocales,
      path: AppLocalization.translationsPath,
      startLocale: AppLocalization.startLocale,
      fallbackLocale: AppLocalization.fallbackLocale,
      child: const IqraWartaqApp(),
    ),
  );
}

class IqraWartaqApp extends StatefulWidget {
  const IqraWartaqApp({super.key});

  @override
  State<IqraWartaqApp> createState() => _IqraWartaqAppState();
}

class _IqraWartaqAppState extends State<IqraWartaqApp> {
  /// Built once per app instance, not once per process, so navigation history
  /// never outlives the widget tree.
  late final GoRouter _router = AppRouter.create();

  StreamSubscription<SettingsState>? _settingsSub;

  /// System until the settings cubit exists and says otherwise.
  ///
  /// A plain field, updated from a stream subscription, rather than a
  /// `BlocBuilder`. A builder is a widget, and a widget appearing in the tree
  /// moves everything beneath it: inserting one above [MaterialApp.router]
  /// would rebuild the `Router` and with it the `Navigator`, tearing down the
  /// splash and restarting its animation mid-flight. The tree shape here is
  /// fixed from the first frame; only this property changes.
  ThemeMode _themeMode = ThemeMode.system;

  /// Watches the chosen theme once the cubit is built.
  void _followTheme(SettingsCubit cubit) {
    _settingsSub = cubit.stream.listen((SettingsState state) {
      final ThemeMode next = _themeModeOf(state.settings.themeMode);
      if (mounted && next != _themeMode) setState(() => _themeMode = next);
    });
  }

  @override
  void dispose() {
    _settingsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Counters must render in the locale's own numeral system — ٣ من ٥ in
    // Arabic, 3 of 5 in English. easy_localization does not set this itself,
    // and `build` runs again on every locale change, so this is where it stays
    // in step.
    Intl.defaultLocale = context.locale.toString();

    // Settings are app-wide: the theme, the Arabic font size and the home
    // view mode are read by more than one screen.
    //
    // `lazy` is the load-bearing part. The provider is mounted from the first
    // frame so the tree shape never changes, but `create` does not run until
    // something below actually reads the cubit — and the only thing on screen
    // until startup finishes is the splash, which reads none of it.
    return BlocProvider<SettingsCubit>(
      lazy: true,
      create: (_) {
        // Reaching `sl` here is safe by construction: the only thing on screen
        // before startup finishes is the splash, which reads no settings, and
        // the splash does not hand over until AppBootstrap has completed. So
        // the first read of this provider is already past initialisation.
        //
        // The provider owns the cubit rather than being handed one built
        // elsewhere. An earlier version kept it in a field that a startup
        // future filled in, and `create` threw when it was still null — which
        // turned any unexpected early build into a hard crash instead of just
        // working. Creating it on demand has no such window.
        final SettingsCubit cubit = sl<SettingsCubit>()..load();
        _followTheme(cubit);
        return cubit;
      },
      child: ScreenUtilInit(
        designSize: const Size(
          AppConstants.designWidth,
          AppConstants.designHeight,
        ),
        minTextAdapt: true,
        builder: (BuildContext context, Widget? child) => MaterialApp.router(
          debugShowCheckedModeBanner: false,
          // onGenerateTitle rather than title: it runs inside a localised
          // context, so the task-switcher label follows the app locale
          // instead of being frozen at startup.
          onGenerateTitle: (BuildContext context) => LocaleKeys.appName.tr(),
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: _themeMode,
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          routerConfig: _router,
        ),
      ),
    );
  }

  static ThemeMode _themeModeOf(AppThemeMode mode) => switch (mode) {
    AppThemeMode.system => ThemeMode.system,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
  };
}
