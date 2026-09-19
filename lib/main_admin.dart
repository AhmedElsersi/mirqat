import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'admin/config/admin_config.dart';
import 'admin/cubit/admin_cubit.dart';
import 'admin/screen/admin_screen.dart';
import 'admin/services/ffmpeg_runner.dart';
import 'admin/services/r2_client.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'data/datasources/asset_reader.dart';
import 'data/datasources/bundle_asset_reader.dart';
import 'data/datasources/quran_database.dart';
import 'data/datasources/quran_local_data_source.dart';
import 'data/repositories/quran_repository.dart';

/// The macOS-only admin tool: split a recording into ayahs, review each one
/// against its text, publish to R2.
///
/// A second entry point rather than a mode of the app, and the separation runs
/// one way only: `lib/main.dart` imports nothing under `lib/admin/`, so none
/// of this — the R2 client, the credentials, the ffmpeg shell-outs — can reach
/// a phone build. `test/admin/admin_isolation_test.dart` holds that line.
///
/// Launched through `./run_admin.sh`, which passes the credentials from
/// `admin.env` as `--dart-define`s. Nothing here has a fallback value; a
/// missing key stops the tool at launch.
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final List<String> missing = AdminConfig.missingKeys;
  if (missing.isNotEmpty) {
    runApp(_Refused(message: AdminConfig.missingMessage(missing)));
    return;
  }

  runApp(AdminApp(config: AdminConfig.fromEnvironment()));
}

class AdminApp extends StatelessWidget {
  const AdminApp({required this.config, super.key});

  final AdminConfig config;

  @override
  Widget build(BuildContext context) {
    // Built here rather than through the app's GetIt: the admin tool shares
    // the repository layer and nothing else, and registering an R2 client in
    // the same locator the app uses is exactly the kind of accident the
    // one-way import rule exists to prevent.
    final AssetReader assets = BundleAssetReader();
    final QuranRepository quran = QuranRepositoryImpl(
      QuranLocalDataSourceImpl(assets, QuranDatabase()),
    );

    // ScreenUtil, even here: `AyahText` sizes itself with `.sp`, and it is the
    // only widget allowed to render Quranic text (CLAUDE.md A.3). Without this
    // the review list throws a LateInitializationError the moment a segment
    // appears beside its ayah — which is exactly when the operator needs it.
    return ScreenUtilInit(
      designSize: const Size(
        AppConstants.designWidth,
        AppConstants.designHeight,
      ),
      minTextAdapt: true,
      builder: (BuildContext context, Widget? _) => MaterialApp(
        title: 'Mirqat admin',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: BlocProvider<AdminCubit>(
          create: (_) => AdminCubit(
            quranRepository: quran,
            adminConfig: config,
            ffmpegRunner: FfmpegRunner(),
            r2Client: R2Client(adminConfig: config),
          )..load(),
          child: const AdminScreen(),
        ),
      ),
    );
  }
}

/// What a build with no credentials shows. Not a dialog over a usable tool:
/// there is nothing usable behind it.
class _Refused extends StatelessWidget {
  const _Refused({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: SelectableText(message, textAlign: TextAlign.center),
        ),
      ),
    ),
  );
}
