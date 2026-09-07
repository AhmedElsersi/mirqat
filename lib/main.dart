import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'core/constants/app_constants.dart';
import 'core/di/injection.dart';
import 'core/localization/app_localization.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/models/app_settings.dart';
import 'features/settings/cubit/settings_cubit.dart';
import 'features/settings/cubit/settings_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await Hive.initFlutter();
  await configureDependencies();

  runApp(
    EasyLocalization(
      supportedLocales: AppLocalization.supportedLocales,
      path: AppLocalization.translationsPath,
      startLocale: AppLocalization.startLocale,
      fallbackLocale: AppLocalization.fallbackLocale,
      child: const TahfizApp(),
    ),
  );
}

class TahfizApp extends StatefulWidget {
  const TahfizApp({super.key});

  @override
  State<TahfizApp> createState() => _TahfizAppState();
}

class _TahfizAppState extends State<TahfizApp> {
  /// Built once per app instance, not once per process, so navigation history
  /// never outlives the widget tree.
  late final GoRouter _router = AppRouter.create();

  @override
  Widget build(BuildContext context) {
    // Settings are app-wide: the theme and the Arabic font size are read by
    // more than one screen.
    return BlocProvider<SettingsCubit>(
      create: (_) => sl<SettingsCubit>()..load(),
      child: ScreenUtilInit(
        designSize: const Size(
          AppConstants.designWidth,
          AppConstants.designHeight,
        ),
        minTextAdapt: true,
        builder: (BuildContext context, Widget? child) =>
            BlocBuilder<SettingsCubit, SettingsState>(
              buildWhen: (SettingsState a, SettingsState b) =>
                  a.settings.themeMode != b.settings.themeMode,
              builder: (BuildContext context, SettingsState state) =>
                  MaterialApp.router(
                    debugShowCheckedModeBanner: false,
                    theme: AppTheme.light,
                    darkTheme: AppTheme.dark,
                    themeMode: _themeModeOf(state.settings.themeMode),
                    locale: context.locale,
                    supportedLocales: context.supportedLocales,
                    localizationsDelegates: context.localizationDelegates,
                    routerConfig: _router,
                  ),
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
