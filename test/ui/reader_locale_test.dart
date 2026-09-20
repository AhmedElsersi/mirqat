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
import 'package:mirqat/data/models/app_settings.dart';
import 'package:mirqat/core/localization/app_localization.dart';
import 'package:mirqat/core/widgets/ayah_text.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:mirqat/features/mushaf/cubit/mushaf_cubit.dart';
import 'package:mirqat/features/mushaf/cubit/mushaf_page.dart';
import 'package:mirqat/features/session/widgets/session_sheet.dart';
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

        await AppHarness.setHomeView(tester, HomeViewMode.grid);
        expect(find.byType(SurahTile), findsWidgets);
        expect(tester.takeException(), isNull);

        await AppHarness.setHomeView(tester, HomeViewMode.list);
        await AppHarness.openReading(tester, find.byType(SurahRow).first);
        expect(tester.takeException(), isNull);

        // The bar and the sheet lay out in both directions, with nothing in
        // either mirrored by hand.
        await AppHarness.showReadingBar(tester);
        expect(tester.takeException(), isNull);
        await AppHarness.openSessionSheet(tester);
        expect(find.byType(SessionSheet), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a separate-preamble surah opens with its basmala line', (
        WidgetTester tester,
      ) async {
        await harness.pumpApp(tester, locale: locale);

        // The first catalog surah that recites the bismillah unnumbered.
        // Al-Fatiha counts it as ayah 1 and gets no line of its own. Chosen
        // by mode, never by surah number.
        final Surah separate = catalog.firstWhere(
          (Surah s) => s.bismillahMode == BismillahMode.separatePreamble,
        );
        final MushafCubit cubit = await AppHarness.openReading(
          tester,
          // The Arabic name is on the row in both locales.
          find.text(separate.nameAr).first,
        );
        expect(tester.takeException(), isNull);

        final MushafPage first = cubit.state.pages[cubit.state.currentPage]!;
        expect(first.lines.whereType<BasmalaLine>(), hasLength(1));
        expect(first.lines.first, isA<SurahHeaderLine>());
      });

      testWidgets('Al-Fatiha has no separate basmala line', (
        WidgetTester tester,
      ) async {
        await harness.pumpApp(tester, locale: locale);

        // The first catalog row counts the bismillah as its ayah 1, so a
        // line of its own would show the same words twice.
        final MushafCubit cubit = await AppHarness.openReading(
          tester,
          find.byType(SurahRow).first,
        );
        expect(tester.takeException(), isNull);
        expect(
          cubit.state.pages[cubit.state.currentPage]!.lines
              .whereType<BasmalaLine>(),
          isEmpty,
        );
        expect(find.byType(AyahText), findsWidgets);
      });

      testWidgets('the reader survives the largest system font scale', (
        WidgetTester tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await harness.pumpApp(tester, locale: locale);
        await AppHarness.openReading(tester, find.byType(SurahRow).first);
        expect(tester.takeException(), isNull);

        await AppHarness.showReadingBar(tester);
        expect(tester.takeException(), isNull);
        await AppHarness.openSessionSheet(tester);
        expect(tester.takeException(), isNull);
      });
    });
  }
}
