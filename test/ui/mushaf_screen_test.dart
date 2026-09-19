import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/localization/app_localization.dart';
import 'package:mirqat/core/widgets/ayah_text.dart';
import 'package:mirqat/features/mushaf/cubit/mushaf_cubit.dart';
import 'package:mirqat/features/mushaf/cubit/mushaf_page.dart';
import 'package:mirqat/features/mushaf/screen/mushaf_screen.dart';
import 'package:mirqat/features/mushaf/widgets/ayah_actions_sheet.dart';
import 'package:mirqat/features/mushaf/widgets/mushaf_page_view.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../app_harness.dart';
import '../quran_db_fixtures.dart';

/// The mushaf screen on the real app, checked against quran.db. Pages and
/// ayahs are found in the data, never typed.
void main() {
  late AppHarness harness;
  late Database db;

  setUpAll(() async => db = await RepoQuranDatabase().open());
  setUp(() async => harness = await AppHarness.start());
  tearDown(() async => harness.stop());
  tearDownAll(AppHarness.disposeAll);

  /// Runs frames for [total], one at a time. A single long pump is a single
  /// frame, which starts an animation without ever advancing it.
  Future<void> frames(WidgetTester tester, [int total = 700]) async {
    for (int t = 0; t < total; t += 16) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Database reads, run where real I/O completes.
  Future<T> real<T>(WidgetTester tester, Future<T> Function() body) async =>
      (await tester.runAsync(body)) as T;

  Future<MushafCubit> openMushaf(
    WidgetTester tester, {
    Locale locale = AppLocalization.arabic,
  }) async {
    await harness.pumpApp(tester, locale: locale);
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.auto_stories_outlined));
      await tester.pump();
      await tester.pump();
    });
    final MushafCubit cubit = BlocProvider.of<MushafCubit>(
      tester.element(find.byType(MushafView)),
    );
    await tester.runAsync(() async {
      for (int i = 0; i < 500; i++) {
        final bool ready = cubit.state.pages.containsKey(
          cubit.state.currentPage,
        );
        if (ready) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await frames(tester);
    return cubit;
  }

  Future<void> showPage(
    WidgetTester tester,
    MushafCubit cubit,
    int page,
  ) async {
    final Map<String, Object?> first = (await real(
      tester,
      () => db.query(
        'ayahs',
        columns: <String>['surah', 'ayah'],
        where: 'page = ?',
        whereArgs: <int>[page],
        orderBy: 'surah, ayah',
        limit: 1,
      ),
    )).single;
    // Every page the turn can show — the ones it passes on a short animated
    // hop, and the neighbours warmed on arrival — is built first, in the real
    // zone. A load the screen starts inside the test's fake-async zone never
    // completes, and the app's connection serialises queries, so a real-zone
    // query queued behind one would wait forever.
    await tester.runAsync(() async {
      final int from = cubit.state.currentPage;
      final int low = (page < from ? page : from) - 1;
      final int high = (page > from ? page : from) + 1;
      final bool hop = (page - from).abs() <= 2;
      for (int p = low; p <= high; p++) {
        if (hop || (p - page).abs() <= 1) await cubit.ensurePage(p);
      }
      await cubit.goToAyah(first['surah']! as int, first['ayah']! as int);
    });
    await frames(tester);
    expect(cubit.state.currentPage, page);
  }

  Finder pageView(int page) => find.byWidgetPredicate(
    (Widget w) => w is MushafPageView && w.page.number == page,
  );

  List<AyahText> renderedWords(WidgetTester tester, int page) => tester
      .widgetList<AyahText>(
        find.descendant(of: pageView(page), matching: find.byType(AyahText)),
      )
      .toList();

  /// What quran.db says the page draws, line by line, as (text, surah, ayah,
  /// isMarker) — surah 0 for basmala-line words, which belong to no ayah.
  Future<List<(String, int, int, bool)>> storedWords(
    WidgetTester tester,
    int page,
  ) => real(tester, () async {
    final String basmalaMode = 'first_ayah';
    final int source =
        (await db.query(
              'surahs',
              columns: <String>['id'],
              where: 'basmala_mode = ?',
              whereArgs: <String>[basmalaMode],
            )).single['id']!
            as int;
    final List<(String, int, int, bool)> basmala = <(String, int, int, bool)>[
      for (final Map<String, Object?> r in await db.query(
        'words',
        where: 'surah = ? AND ayah = 1 AND is_marker = 0',
        whereArgs: <int>[source],
        orderBy: 'id',
      ))
        (r['text']! as String, 0, 0, false),
    ];

    final List<(String, int, int, bool)> out = <(String, int, int, bool)>[];
    for (final Map<String, Object?> line in await db.query(
      'lines',
      where: 'page = ?',
      whereArgs: <int>[page],
      orderBy: 'line',
    )) {
      switch (line['line_type']) {
        case 'basmallah':
          out.addAll(basmala);
        case 'ayah':
          for (final Map<String, Object?> w in await db.query(
            'words',
            where: 'id BETWEEN ? AND ?',
            whereArgs: <Object?>[line['first_word_id'], line['last_word_id']],
            orderBy: 'id',
          )) {
            out.add((
              w['text']! as String,
              w['surah']! as int,
              w['ayah']! as int,
              w['is_marker'] == 1,
            ));
          }
      }
    }
    return out;
  });

  void expectByteIdentical(
    List<AyahText> rendered,
    List<(String, int, int, bool)> stored,
  ) {
    expect(rendered.length, stored.length);
    for (int i = 0; i < stored.length; i++) {
      expect(
        rendered[i].text.codeUnits,
        stored[i].$1.codeUnits,
        reason: 'word $i differs from quran.db',
      );
      expect(rendered[i].isMarker, stored[i].$4, reason: 'word $i marker flag');
    }
  }

  group('text reaching the renderer is byte-identical to quran.db', () {
    testWidgets('page 1', (WidgetTester tester) async {
      await openMushaf(tester);
      expectByteIdentical(
        renderedWords(tester, 1),
        await storedWords(tester, 1),
      );
    });

    testWidgets('pages holding tatweel-carrier ayahs', (
      WidgetTester tester,
    ) async {
      final MushafCubit cubit = await openMushaf(tester);

      // One ayah per distinct page among the tatweel carriers, three pages.
      final List<Map<String, Object?>> carriers = await real(
        tester,
        () => db.rawQuery(
          'SELECT surah, ayah, page, text FROM ayahs a '
          'WHERE instr(text, char(1600)) > 0 AND NOT EXISTS ('
          '  SELECT 1 FROM words w WHERE w.surah = a.surah '
          '  AND w.ayah = a.ayah AND w.page <> a.page) '
          'GROUP BY page ORDER BY page LIMIT 3',
        ),
      );
      expect(carriers, hasLength(3));

      for (final Map<String, Object?> carrier in carriers) {
        final int page = carrier['page']! as int;
        await showPage(tester, cubit, page);

        final List<AyahText> rendered = renderedWords(tester, page);
        final List<(String, int, int, bool)> stored = await storedWords(
          tester,
          page,
        );
        expectByteIdentical(rendered, stored);

        // And the ayah itself, as drawn: its words joined are its stored
        // text, tatweel carriers and all.
        final int surah = carrier['surah']! as int;
        final int ayah = carrier['ayah']! as int;
        final String drawn = <String>[
          for (int i = 0; i < stored.length; i++)
            if (stored[i].$2 == surah && stored[i].$3 == ayah && !stored[i].$4)
              rendered[i].text,
        ].join(' ');
        expect(
          drawn.codeUnits,
          (carrier['text']! as String).codeUnits,
          reason: '$surah:$ayah as drawn differs from ayahs.text',
        );
      }
    });
  });

  group('layout', () {
    for (final Size size in <Size>[
      const Size(320, 568),
      const Size(390, 844),
      const Size(1024, 1366),
    ]) {
      testWidgets('short, full and last pages fit ${size.width}x${size.height} '
          'without scrolling', (WidgetTester tester) async {
        tester.view.physicalSize = size * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final MushafCubit cubit = await openMushaf(tester);
        final List<int> pages = await real(tester, () async {
          final List<Map<String, Object?>> counts = await db.rawQuery(
            'SELECT page, COUNT(*) AS n FROM lines GROUP BY page ORDER BY page',
          );
          final int full = counts
              .map((Map<String, Object?> r) => r['n']! as int)
              .reduce((int a, int b) => a > b ? a : b);
          return <int>[
            counts.firstWhere((r) => (r['n']! as int) < full)['page']! as int,
            counts.firstWhere((r) => (r['n']! as int) == full)['page']! as int,
            counts.last['page']! as int,
          ];
        });

        for (final int page in pages) {
          await showPage(tester, cubit, page);
          expect(tester.takeException(), isNull, reason: 'page $page');
          expect(
            find.descendant(
              of: pageView(page),
              matching: find.byType(Scrollable),
            ),
            findsNothing,
            reason: 'page $page must not scroll',
          );
        }
      });
    }
  });

  group('taps', () {
    testWidgets('a word opens its ayah; a marker opens nothing', (
      WidgetTester tester,
    ) async {
      await openMushaf(tester);
      final List<AyahText> words = renderedWords(tester, 1);

      await tester.tap(
        find.byWidget(words.firstWhere((AyahText w) => w.isMarker)),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AyahActionsSheet), findsNothing);

      // The first word on Al-Fatiha's page is its ayah 1 — the basmala,
      // counted as that ayah — and selects like any other word.
      await tester.tap(find.byWidget(words.first));
      await tester.pump(const Duration(milliseconds: 400));
      final AyahActionsSheet sheet = tester.widget(
        find.byType(AyahActionsSheet),
      );
      expect(sheet.ayah, const AyahRef(1, 1));
    });

    testWidgets('a separate basmala line selects nothing', (
      WidgetTester tester,
    ) async {
      final MushafCubit cubit = await openMushaf(tester);
      final int page = await real(
        tester,
        () async =>
            (await db.query(
                  'lines',
                  columns: <String>['page'],
                  where: "line_type = 'basmallah'",
                  orderBy: 'page',
                  limit: 1,
                )).single['page']!
                as int,
      );
      await showPage(tester, cubit, page);

      final int basmalaWordCount =
          (cubit.state.pages[page]!.lines.whereType<BasmalaLine>().first)
              .words
              .length;
      // The basmala line is the first run of AyahText words on the page.
      final AyahText basmalaWord = renderedWords(tester, page).first;
      expect(basmalaWordCount, greaterThan(0));

      await tester.tap(find.byWidget(basmalaWord), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AyahActionsSheet), findsNothing);
      expect(cubit.state.selected, isNull);
    });
  });

  group('page turning', () {
    for (final Locale locale in AppLocalization.supportedLocales) {
      testWidgets('dragging rightwards turns to the next page '
          '(${locale.languageCode})', (WidgetTester tester) async {
        final MushafCubit cubit = await openMushaf(tester, locale: locale);
        expect(cubit.state.currentPage, 1);
        // Built up front, for the same reason as in showPage: arriving on page
        // 2 warms page 3, and a load started in this zone would hold the
        // shared connection past the end of the test.
        await tester.runAsync(() async {
          await cubit.ensurePage(2);
          await cubit.ensurePage(3);
        });

        // Leftwards first: page 1 is the first page, there is nothing before
        // it on the right.
        await tester.fling(find.byType(PageView), const Offset(-300, 0), 1500);
        await frames(tester);
        expect(cubit.state.currentPage, 1);

        await tester.fling(find.byType(PageView), const Offset(300, 0), 1500);
        await frames(tester);
        expect(cubit.state.currentPage, 2);
      });
    }
  });

  testWidgets('highlightAyah tints exactly that ayah\'s words', (
    WidgetTester tester,
  ) async {
    final MushafCubit cubit = await openMushaf(tester);
    cubit.highlightAyah(1, 2);
    await frames(tester, 100);

    final List<Map<String, Object?>> rows = await real(
      tester,
      () => db.query(
        'words',
        columns: <String>['text'],
        where: 'surah = 1 AND ayah = 2 AND is_marker = 0',
      ),
    );
    final Set<String> texts = <String>{
      for (final Map<String, Object?> r in rows) r['text']! as String,
    };
    final List<AyahText> tinted = renderedWords(
      tester,
      1,
    ).where((AyahText w) => w.tint == WordTint.highlighted).toList();

    expect(tinted, hasLength(rows.length));
    expect(tinted.every((AyahText w) => texts.contains(w.text)), isTrue);
  });
}
