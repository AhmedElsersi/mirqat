import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mirqat/core/router/app_routes.dart';
import 'package:mirqat/features/about/screen/about_screen.dart';
import 'package:mirqat/features/backup/screen/backup_screen.dart';
import 'package:mirqat/features/hifz_plan/screen/hifz_plan_screen.dart';
import 'package:mirqat/features/history/screen/history_screen.dart';
import 'package:mirqat/features/home/screen/home_shell.dart';
import 'package:mirqat/features/review/screen/reviews_screen.dart';
import 'package:mirqat/features/search/screen/search_screen.dart';
import 'package:mirqat/features/settings/screen/downloads_screen.dart';
import 'package:mirqat/features/settings/screen/mushaf_download_screen.dart';
import 'package:mirqat/features/settings/screen/mushaf_font_screen.dart';
import 'package:mirqat/features/settings/screen/session_settings_screen.dart';
import 'package:mirqat/features/similar/screen/mutashabihat_screen.dart';
import 'package:mirqat/features/stats/screen/stats_screen.dart';
import 'package:mirqat/features/weak_spots/screen/weak_spots_screen.dart';

import '../app_harness.dart';

/// Every screen reached from the four tabs, opened on a 320 dp phone.
///
/// Not an assertion about what they say — each has its own test for that —
/// but about the one way a redesigned screen fails silently: a row of chips,
/// tags and buttons that fits the design width and overflows a narrow one.
void main() {
  late AppHarness harness;
  late Directory documents;

  setUp(() async {
    harness = await AppHarness.start();
    // The backup screen asks the device for its documents folder, which is a
    // platform channel with no host under `flutter test`.
    documents = Directory.systemTemp.createTempSync('mirqat-documents');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall call) async =>
              call.method == 'getApplicationDocumentsDirectory'
              ? documents.path
              : null,
        );
  });
  tearDown(() async {
    await harness.stop();
    if (documents.existsSync()) documents.deleteSync(recursive: true);
  });
  tearDownAll(AppHarness.disposeAll);

  const Map<String, Type> screens = <String, Type>{
    AppRoutes.searchName: SearchScreen,
    AppRoutes.historyName: HistoryScreen,
    AppRoutes.reviewsName: ReviewsScreen,
    AppRoutes.hifzPlanName: HifzPlanScreen,
    AppRoutes.weakSpotsName: WeakSpotsScreen,
    AppRoutes.statsName: StatsScreen,
    AppRoutes.mutashabihatName: MutashabihatScreen,
    AppRoutes.downloadsName: DownloadsScreen,
    AppRoutes.mushafDownloadName: MushafDownloadScreen,
    AppRoutes.mushafFontName: MushafFontScreen,
    AppRoutes.sessionSettingsName: SessionSettingsScreen,
    AppRoutes.backupName: BackupScreen,
    AppRoutes.aboutName: AboutScreen,
  };

  for (final MapEntry<String, Type> screen in screens.entries) {
    testWidgets('${screen.key} lays out at 320 dp', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await harness.pumpApp(tester);
      final BuildContext context = tester.element(find.byType(HomeShell));
      GoRouter.of(context).pushNamed(screen.key);
      // Real time, not `settle`: the reads a screen makes on the way in are
      // file and database I/O, and a screen still on its spinner never
      // settles — the spinner animates for as long as it is there.
      await AppHarness.settleReads(tester);
      await AppHarness.frames(tester, 300);

      expect(find.byType(screen.value), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
