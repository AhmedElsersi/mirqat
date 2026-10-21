import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/widgets/ayah_text.dart';
import 'package:mirqat/data/models/app_settings.dart';
import 'package:mirqat/data/models/word.dart';
import 'package:mirqat/features/mushaf/cubit/mushaf_page.dart';
import 'package:mirqat/features/mushaf/widgets/mushaf_page_view.dart';

/// Two ayahs on one line, each of three words and a marker, then a line
/// that belongs to the neighbouring surah — printed, but not being read.
int _id = 0;
Word word(int ayah, int position, {bool marker = false, int surah = 2}) => Word(
  id: ++_id,
  surahNumber: surah,
  ayahNumber: ayah,
  position: position,
  text: marker ? '$ayah' : 'w$ayah-$position',
  isMarker: marker,
  page: 5,
  line: 1,
);

MushafPage page() {
  _id = 0;
  return MushafPage(
    number: 5,
    lines: <PageLine>[
      AyahLine(
        centered: false,
        words: <Word>[
          for (int p = 1; p <= 3; p++) word(1, p),
          word(1, 4, marker: true),
          for (int p = 1; p <= 3; p++) word(2, p),
          word(2, 4, marker: true),
        ],
      ),
      AyahLine(
        centered: false,
        words: <Word>[for (int p = 1; p <= 3; p++) word(9, p, surah: 3)],
      ),
    ],
  );
}

void main() {
  late int pageTaps;

  Future<void> pump(
    WidgetTester tester, {
    MemorizationView view = MemorizationView.off,
    AyahRef? veiled,
    ValueChanged<Word>? onWordTap,
  }) async {
    pageTaps = 0;
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          home: Scaffold(
            body: MushafPageView(
              page: page(),
              linesPerFullPage: 15,
              highlighted: null,
              veiled: veiled,
              memorizationView: view,
              selected: null,
              onWordLongPress: (_) {},
              onTap: () => pageTaps++,
              onWordTap: onWordTap,
              isHeldBack: (Word w) => w.surahNumber == 3,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Every word drawn, by its text, and whether its ink is withheld.
  Map<String, bool> covered(WidgetTester tester) => <String, bool>{
    for (final AyahText t in tester.widgetList<AyahText>(find.byType(AyahText)))
      t.text: t.veiled,
  };

  testWidgets('off: the page as it is printed', (WidgetTester tester) async {
    await pump(tester);
    expect(covered(tester).values, everyElement(isFalse));
  });

  testWidgets('first words: each ayah keeps its first word as the cue', (
    WidgetTester tester,
  ) async {
    await pump(tester, view: MemorizationView.firstWords);
    final Map<String, bool> c = covered(tester);
    expect(c['w1-1'], isFalse);
    expect(c['w1-2'], isTrue);
    expect(c['w1-3'], isTrue);
    expect(c['w2-1'], isFalse);
    expect(c['w2-3'], isTrue);
  });

  testWidgets('hidden: every recited word, never a marker, never a word '
      'that is only on the page beside the section', (
    WidgetTester tester,
  ) async {
    await pump(tester, view: MemorizationView.markersOnly);
    final Map<String, bool> c = covered(tester);
    for (final String w in <String>['w1-1', 'w1-2', 'w2-1', 'w2-3']) {
      expect(c[w], isTrue, reason: w);
    }
    expect(c['1'], isFalse, reason: 'a marker says where the ayah ends');
    expect(c['2'], isFalse);
    expect(c['w9-1'], isFalse, reason: 'held back, not the reader\'s');
  });

  testWidgets('a tap on a covered word uncovers its ayah alone; the next tap '
      'covers it again — and neither turns the bar on', (
    WidgetTester tester,
  ) async {
    await pump(tester, view: MemorizationView.markersOnly);

    await tester.tap(find.text('w2-2'));
    await tester.pump();
    Map<String, bool> c = covered(tester);
    expect(c['w2-1'], isFalse);
    expect(c['w2-3'], isFalse);
    expect(c['w1-1'], isTrue, reason: 'only the tapped ayah');

    await tester.tap(find.text('w2-2'));
    await tester.pump();
    c = covered(tester);
    expect(c['w2-1'], isTrue);
    expect(pageTaps, 0);
  });

  testWidgets('with the view off, a tap is the page\'s as before', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('w1-2'));
    await tester.pump();
    expect(pageTaps, 1);
  });

  testWidgets('a recall round still veils its ayah with the view off', (
    WidgetTester tester,
  ) async {
    await pump(tester, veiled: const AyahRef(2, 2));
    final Map<String, bool> c = covered(tester);
    expect(c['w2-2'], isTrue);
    expect(c['w1-2'], isFalse);
    expect(c['2'], isFalse);
  });

  testWidgets('the words are still the words: covering never changes text', (
    WidgetTester tester,
  ) async {
    await pump(tester, view: MemorizationView.markersOnly);
    expect(find.text('w1-2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a word tap the screen asks for goes to it, and nothing else '
      'happens: no peek, no bar', (WidgetTester tester) async {
    final List<String> tapped = <String>[];
    await pump(
      tester,
      view: MemorizationView.markersOnly,
      onWordTap: (Word w) => tapped.add(w.text),
    );
    await tester.tap(find.text('w2-2'));
    await tester.pump();
    expect(tapped, <String>['w2-2']);
    expect(covered(tester)['w2-1'], isTrue, reason: 'nothing peeked');
    expect(pageTaps, 0);
  });

  test('the view is read forgivingly from storage', () {
    expect(
      MemorizationView.fromStorage('first_words'),
      MemorizationView.firstWords,
    );
    expect(MemorizationView.fromStorage('nonsense'), MemorizationView.off);
    expect(MemorizationView.fromStorage(3), MemorizationView.off);
    const AppSettings s = AppSettings(
      memorizationView: MemorizationView.markersOnly,
    );
    expect(AppSettings.fromMap(s.toMap()), s);
    expect(
      AppSettings.fromMap(<String, dynamic>{}).memorizationView,
      MemorizationView.off,
    );
  });
}
