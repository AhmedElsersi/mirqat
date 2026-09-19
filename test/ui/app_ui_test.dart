import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/data/models/app_settings.dart';
import 'package:mirqat/core/constants/asset_paths.dart';
import 'package:mirqat/core/localization/app_localization.dart';
import 'package:mirqat/core/widgets/ayah_text.dart';
import 'package:mirqat/core/widgets/session_controls.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:mirqat/features/reader/screen/reader_screen.dart';
import 'package:mirqat/features/reader/widgets/audio_pack_tile.dart';
import 'package:mirqat/features/reader/widgets/session_drawer.dart';
import 'package:mirqat/features/surah_list/widgets/reading_only_marker.dart';
import 'package:mirqat/features/surah_list/widgets/surah_row.dart';
import 'package:mirqat/features/surah_list/widgets/surah_tile.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../app_harness.dart';
import '../quran_db_fixtures.dart';

void main() {
  late AppHarness harness;
  late List<Surah> catalog;

  late Set<int> recordedSurahs;
  late Map<String, dynamic> arabic;

  setUpAll(() async {
    // What the app treats as recorded is the *merged* catalog: surahs that
    // ship in the bundle, plus surahs the manifest offers. Since the audio
    // moved to the CDN the first set is empty and the second is everything, so
    // reading only `reciters.json` here would call every surah unrecorded.
    recordedSurahs = <int>{
      for (final dynamic r
          in jsonDecode(File(AssetPaths.recitersCatalog).readAsStringSync())
              as List<dynamic>)
        ...((r as Map<String, dynamic>)['availableSurahs'] as List<dynamic>)
            .cast<int>(),
      for (final dynamic r
          in (jsonDecode(testManifest) as Map<String, dynamic>)['reciters']
              as List<dynamic>)
        for (final dynamic s
            in (r as Map<String, dynamic>)['surahs'] as List<dynamic>)
          (s as Map<String, dynamic>)['n'] as int,
    };
    arabic =
        jsonDecode(File('assets/translations/ar.json').readAsStringSync())
            as Map<String, dynamic>;
    final Database db = await RepoQuranDatabase().open();
    catalog = (await db.query(
      'surahs',
      orderBy: 'id',
    )).map(Surah.fromDbRow).toList();
  });

  setUp(() async => harness = await AppHarness.start());
  tearDown(() async => harness.stop());
  tearDownAll(AppHarness.disposeAll);

  /// Opens the first row — Al-Fatiha, since the catalog is ascending. The
  /// harness only fakes clip durations for surah 1, so the session summary is
  /// exercised against real measured numbers rather than invented ones.
  Future<void> openReader(WidgetTester tester) async {
    await AppHarness.tapAndSettle(tester, find.byType(SurahRow).first);
  }

  /// The session summary now lives in the reader's end drawer, so reaching it
  /// means opening the drawer.
  Future<void> openDrawer(WidgetTester tester) async {
    await AppHarness.tapAndSettle(tester, find.byIcon(Icons.tune));
  }

  group('localisation and direction', () {
    testWidgets('launches in Arabic, laid out right to left', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);

      final BuildContext context = tester.element(find.byType(Scaffold).first);
      expect(Localizations.localeOf(context).languageCode, 'ar');
      expect(Directionality.of(context), TextDirection.rtl);
    });

    testWidgets('mirrors to left-to-right when forced to English', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester, locale: AppLocalization.english);

      final BuildContext context = tester.element(find.byType(Scaffold).first);
      expect(Localizations.localeOf(context).languageCode, 'en');
      expect(Directionality.of(context), TextDirection.ltr);
      // The wordmark is the brand's name, so it is the Arabic string on both
      // locales (owner decision D1).
      expect(find.text('اقرأ وارتق'), findsOneWidget);
    });

    testWidgets('no user-facing string is a raw translation key', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);

      for (final Text widget in tester.widgetList<Text>(find.byType(Text))) {
        final String? data = widget.data;
        if (data == null) continue;
        expect(
          data.contains('.') && !data.contains(' ') && data.length > 6,
          isFalse,
          reason: 'looks like an untranslated key: "$data"',
        );
      }
    });
  });

  group('surah list', () {
    testWidgets('lists every surah in the catalog, with no placeholder rows', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);

      // The list is lazy, so rows are counted off its declared length rather
      // than the handful built on screen — and that length off quran.db, not
      // a number typed here.
      expect(_itemCount(tester, ListView), catalog.length);
      expect(find.text(catalog.first.nameAr), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text(catalog.last.nameAr),
        600,
        scrollable: AppHarness.homeScrollable(ListView),
      );
      expect(find.text(catalog.last.nameAr), findsOneWidget);
    });

    testWidgets('the chosen view switches to a grid and persists', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);

      expect(_itemCount(tester, ListView), catalog.length);
      expect(find.byType(SurahTile), findsNothing);

      await AppHarness.setHomeView(tester, HomeViewMode.grid);

      expect(_itemCount(tester, GridView), catalog.length);
      expect(find.byType(SurahRow), findsNothing);

      // Restarting proves the choice was written, not just held in memory.
      await harness.pumpApp(tester);
      expect(_itemCount(tester, GridView), catalog.length);

      // And back again.
      await AppHarness.setHomeView(tester, HomeViewMode.list);
      expect(_itemCount(tester, ListView), catalog.length);
    });

    testWidgets('a grid tile opens the same reader as a row', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      await AppHarness.setHomeView(tester, HomeViewMode.grid);

      await AppHarness.tapAndSettle(tester, find.byType(SurahTile).first);

      expect(find.byType(ReaderScreen), findsOneWidget);
    });
    testWidgets('marks a surah no reciter has recorded as reading only, and '
        'only that', (WidgetTester tester) async {
      await harness.pumpApp(tester);

      final Surah recorded = catalog.firstWhere(
        (Surah s) => recordedSurahs.contains(s.number),
      );
      final Surah unrecorded = catalog.firstWhere(
        (Surah s) => !recordedSurahs.contains(s.number),
      );

      Finder markerIn(Surah surah) => find.descendant(
        of: find.ancestor(
          of: find.text(surah.nameAr),
          matching: find.byType(SurahRow),
        ),
        matching: find.byType(ReadingOnlyMarker),
      );

      await tester.scrollUntilVisible(
        find.text(unrecorded.nameAr),
        300,
        scrollable: AppHarness.homeScrollable(ListView),
      );
      expect(markerIn(unrecorded), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text(recorded.nameAr),
        -300,
        scrollable: AppHarness.homeScrollable(ListView),
      );
      expect(markerIn(recorded), findsNothing);
    });
  });

  group('reader', () {
    testWidgets('a surah nobody has recorded is readable, with the session '
        'blocked and the reason shown up front', (WidgetTester tester) async {
      await harness.pumpApp(tester);
      final Surah unrecorded = catalog.firstWhere(
        (Surah s) => !recordedSurahs.contains(s.number),
      );

      await tester.scrollUntilVisible(
        find.text(unrecorded.nameAr),
        300,
        scrollable: AppHarness.homeScrollable(ListView),
      );
      await AppHarness.tapAndSettle(tester, find.text(unrecorded.nameAr));

      expect(find.byType(ReaderScreen), findsOneWidget);
      expect(find.byType(AyahText), findsWidgets, reason: 'it is readable');
      expect(
        find.text(
          arabic['reader']['no_audio'].replaceFirst('{}', unrecorded.nameAr),
        ),
        findsOneWidget,
      );

      final ButtonStyleButton play = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.byIcon(Icons.play_arrow),
          matching: find.byWidgetPredicate(
            (Widget w) => w is ButtonStyleButton,
          ),
        ),
      );
      expect(play.onPressed, isNull, reason: 'no session can start');
    });

    testWidgets('a recorded surah shows no block notice', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      await openReader(tester);

      expect(find.byIcon(Icons.info_outline), findsNothing);
    });

    testWidgets('tapping a surah lands on the text, with no dialog', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      await openReader(tester);

      expect(find.byType(ReaderScreen), findsOneWidget);
      // The surah is rendered, and as one flowing block rather than a card
      // per ayah.
      expect(find.byType(AyahText), findsOneWidget);
      // Nothing is standing in front of it.
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(SessionDrawer), findsNothing);
      // The whole surah is the default selection.
      expect(find.text('السورة كاملة'), findsOneWidget);
    });

    testWidgets('summarises the default full-surah session in the drawer', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      await openReader(tester);
      await openDrawer(tester);

      // Full Al-Fatiha, N=3, continuous — the fresh-install default: one
      // step, 7 * 3 = 21 recitations.
      final SessionSummary summary = tester.widget<SessionSummary>(
        find.byType(SessionSummary),
      );
      expect(summary.stepCount, 1);
      expect(summary.unitCount, 21);
      expect(summary.duration, isNotEmpty);
    });

    testWidgets('the drawer offers to download a surah that streams', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      await openReader(tester);
      await openDrawer(tester);

      expect(find.byType(AudioPackTile), findsOneWidget);
      // No surah audio ships any more: Al-Fatiha comes from the manifest, so
      // the line says where it comes from and offers to keep it.
      expect(find.text('يُبَثّ عبر الإنترنت'), findsOneWidget);
      expect(find.byIcon(Icons.download_outlined), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets('the drawer summary tracks the repeat count live', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      await openReader(tester);
      await openDrawer(tester);

      // Steppers in the drawer, in order: range from, range to, repeat count.
      await AppHarness.tapAndSettle(tester, find.byIcon(Icons.add).at(2));

      final SessionSummary summary = tester.widget<SessionSummary>(
        find.byType(SessionSummary),
      );
      // N=4 over 7 ayahs, continuous: still one step, 28 recitations.
      expect(summary.stepCount, 1);
      expect(summary.unitCount, 28);
    });

    testWidgets('tap-to-select and the drawer stay in sync', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      await openReader(tester);

      // Narrow the range from the drawer, then read it off the bottom bar.
      await openDrawer(tester);
      // "From" stepper up twice: ayahs 3..7.
      await AppHarness.tapAndSettle(tester, find.byIcon(Icons.add).first);
      await AppHarness.tapAndSettle(tester, find.byIcon(Icons.add).first);

      final SessionSummary summary = tester.widget<SessionSummary>(
        find.byType(SessionSummary),
      );
      // 5 ayahs x 3 passes.
      expect(summary.unitCount, 15);

      await AppHarness.tapAndSettle(tester, find.byIcon(Icons.close));

      // The bottom bar reflects the drawer's range, in Arabic numerals.
      expect(find.text('الآيات ٣ - ٧'), findsOneWidget);
      expect(find.text('السورة كاملة'), findsNothing);
    });

    testWidgets('a single-ayah range still produces a startable plan', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      await openReader(tester);
      await openDrawer(tester);

      // Pull "to" down to 1, so from == to == 1.
      for (int i = 0; i < 6; i++) {
        await AppHarness.tapAndSettle(tester, find.byIcon(Icons.remove).at(1));
      }

      final SessionSummary summary = tester.widget<SessionSummary>(
        find.byType(SessionSummary),
      );
      expect(summary.unitCount, 3);

      await AppHarness.tapAndSettle(tester, find.byIcon(Icons.close));

      expect(find.text('الآية ١'), findsOneWidget);
      final FilledButton play = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'ابدأ الجلسة'),
      );
      expect(play.onPressed, isNotNull);
    });
  });

  group('layout resilience', () {
    testWidgets('does not overflow at 320 dp wide', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await harness.pumpApp(tester);
      expect(tester.takeException(), isNull);

      await AppHarness.setHomeView(tester, HomeViewMode.grid);
      expect(tester.takeException(), isNull);

      await AppHarness.tapAndSettle(tester, find.byType(SurahTile).first);
      expect(tester.takeException(), isNull);

      await openDrawer(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not overflow at the largest system font scale', (
      WidgetTester tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await harness.pumpApp(tester);
      expect(tester.takeException(), isNull);

      // The list first, then the grid: long surah names at 2x are where a
      // fixed-height tile would clip.
      await openReader(tester);
      expect(tester.takeException(), isNull);

      await openDrawer(tester);
      expect(tester.takeException(), isNull);

      await harness.pumpApp(tester);
      await AppHarness.setHomeView(tester, HomeViewMode.grid);
      expect(tester.takeException(), isNull);
    });
  });
}

/// The declared length of the home list or grid.
int? _itemCount(WidgetTester tester, Type scrollView) =>
    (tester.widget(find.byType(scrollView)) as ScrollView).semanticChildCount;
