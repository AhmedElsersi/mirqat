/// Every screen this change set touched, walked in both locales.
///
/// The layout tests in `app_ui_test` run in Arabic only, which is the wrong
/// direction to catch a hardcoded `EdgeInsets.left` or a Row that only fits
/// one way round. These walk the same screens under both `ar` (RTL) and `en`
/// (LTR) and assert that nothing throws and nothing overflows — a render
/// overflow surfaces as an exception through `takeException`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/localization/app_localization.dart';
import 'package:mirqat/core/widgets/ayah_text.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:mirqat/features/reader/widgets/session_drawer.dart';
import 'package:mirqat/features/surah_list/widgets/surah_row.dart';
import 'package:mirqat/features/surah_list/widgets/surah_tile.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../app_harness.dart';
import '../quran_db_fixtures.dart';

void main() {
  late AppHarness harness;
  late List<Surah> catalog;

  setUpAll(() async {
    final Database db = await RepoQuranDatabase().open();
    catalog = (await db.query(
      'surahs',
      orderBy: 'id',
    )).map(Surah.fromDbRow).toList();
  });

  setUp(() async => harness = await AppHarness.start());
  tearDown(() async => harness.stop());
  tearDownAll(AppHarness.disposeAll);

  for (final Locale locale in AppLocalization.supportedLocales) {
    final String tag = locale.languageCode;
    final TextDirection expected = tag == 'ar'
        ? TextDirection.rtl
        : TextDirection.ltr;

    group(tag, () {
      testWidgets('home list, grid and reader all lay out', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = const Size(390 * 3, 844 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await harness.pumpApp(tester, locale: locale);
        expect(
          Directionality.of(tester.element(find.byType(Scaffold).first)),
          expected,
        );
        expect(tester.takeException(), isNull);

        await AppHarness.tapAndSettle(
          tester,
          find.byIcon(Icons.grid_view_outlined),
        );
        expect(find.byType(SurahTile), findsWidgets);
        expect(tester.takeException(), isNull);

        await AppHarness.tapAndSettle(
          tester,
          find.byIcon(Icons.view_list_outlined),
        );
        await AppHarness.tapAndSettle(tester, find.byType(SurahRow).first);
        expect(tester.takeException(), isNull);

        // The drawer is an endDrawer, so Directionality decides which edge it
        // comes from. Nothing in the widget mirrors anything by hand, which is
        // what this asserts: it opens in both directions.
        await AppHarness.tapAndSettle(tester, find.byIcon(Icons.tune));
        expect(find.byType(SessionDrawer), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a separate-preamble surah renders its bismillah header', (
        WidgetTester tester,
      ) async {
        await harness.pumpApp(tester, locale: locale);

        // The first catalog surah that recites the bismillah unnumbered.
        // Al-Fatiha counts it as ayah 1 and gets no header. Chosen by mode,
        // never by surah number.
        final Surah separate = catalog.firstWhere(
          (Surah s) => s.bismillahMode == BismillahMode.separatePreamble,
        );
        await AppHarness.tapAndSettle(tester, find.text(separate.nameAr));
        expect(tester.takeException(), isNull);

        // Two AyahText widgets: the unnumbered header, and the flowing surah.
        expect(find.byType(AyahText), findsNWidgets(2));
      });

      testWidgets('Al-Fatiha renders no separate bismillah header', (
        WidgetTester tester,
      ) async {
        await harness.pumpApp(tester, locale: locale);

        // The first catalog row counts the bismillah as its ayah 1, so a
        // header would show the same words twice.
        await AppHarness.tapAndSettle(tester, find.byType(SurahRow).first);
        expect(tester.takeException(), isNull);
        expect(find.byType(AyahText), findsOneWidget);
      });

      testWidgets('the reader survives the largest system font scale', (
        WidgetTester tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await harness.pumpApp(tester, locale: locale);
        await AppHarness.tapAndSettle(tester, find.byType(SurahRow).first);
        expect(tester.takeException(), isNull);

        await AppHarness.tapAndSettle(tester, find.byIcon(Icons.tune));
        expect(tester.takeException(), isNull);
      });
    });
  }
}
