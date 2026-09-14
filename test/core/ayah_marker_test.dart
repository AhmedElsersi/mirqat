import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/widgets/ayah_text.dart';

/// The end-of-ayah medallion, and the one mistake it invites.
///
/// U+06DD ARABIC END OF AYAH reads like the correct character: Unicode
/// describes it as enclosing the digits that follow, so `U+06DD` + digits looks
/// like the textbook way to draw a numbered medallion. In the shipped KFGQPC
/// Hafs face it is not. Measured from the font's own tables:
///
///   * `GSUB` lookup 36 ligates a sequence of Arabic-Indic digits directly into
///     one pre-composed glyph, 1477 x 1825 units on a 2048 em — the numbered
///     medallion, as a single glyph. There are 664 of them, one per ayah
///     number.
///   * U+06DD is an independent glyph with the same 1477 x 1825 box and a
///     positive 1595 advance — the same rosette, empty, taking its own space.
///
/// Emit both and the reader gets two medallions side by side, one numbered and
/// one blank. That shipped once. These tests are the tripwire.
void main() {
  group('ayahNumberMarker', () {
    test('is Arabic-Indic digits and nothing else', () {
      expect(AyahText.ayahNumberMarker(1), '١');
      expect(AyahText.ayahNumberMarker(7), '٧');
      expect(AyahText.ayahNumberMarker(12), '١٢');
      expect(AyahText.ayahNumberMarker(286), '٢٨٦');
    });

    test('never contains U+06DD, at any ayah number', () {
      // The whole range a surah can reach, so this cannot pass by only
      // checking a number whose digits happen to avoid the bug.
      for (int n = 1; n <= 286; n++) {
        final String marker = AyahText.ayahNumberMarker(n);
        expect(
          marker.contains('۝'),
          isFalse,
          reason:
              'ayah $n marker carries U+06DD, which draws a second, empty '
              'medallion beside the numbered one',
        );
        // And nothing else sneaks in either: digits only, no separators, no
        // Western numerals, no spaces.
        for (final int unit in marker.codeUnits) {
          expect(
            unit,
            allOf(greaterThanOrEqualTo(0x0660), lessThanOrEqualTo(0x0669)),
            reason:
                'ayah $n marker contains U+${unit.toRadixString(16).toUpperCase()}',
          );
        }
      }
    });

    test('stays in Arabic-Indic digits — it is not a UI number', () {
      // The marker belongs to the mushaf page, not the interface, so it does
      // not follow the UI locale's numeral system. Western digits here would
      // mean someone routed it through `toLocalisedString()`.
      final String marker = AyahText.ayahNumberMarker(123);
      expect(marker, isNot(contains('1')));
      expect(marker, isNot(contains('2')));
      expect(marker, isNot(contains('3')));
    });
  });

  group('the flowing span tree', () {
    /// The spans [AyahText.flowing] actually builds, flattened.
    Future<List<InlineSpan>> spansOf(
      WidgetTester tester,
      List<FlowingAyah> ayahs,
    ) async {
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (BuildContext context, Widget? _) => MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: AyahText.flowing(ayahs: ayahs, fontSize: 24),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final RichText rich = tester.widget<RichText>(find.byType(RichText));
      final List<InlineSpan> out = <InlineSpan>[];
      rich.text.visitChildren((InlineSpan span) {
        out.add(span);
        return true;
      });
      return out;
    }

    testWidgets('renders exactly one marker per ayah, none with U+06DD', (
      WidgetTester tester,
    ) async {
      const List<FlowingAyah> ayahs = <FlowingAyah>[
        FlowingAyah(number: 1, text: 'ayah one'),
        FlowingAyah(number: 2, text: 'ayah two'),
        FlowingAyah(number: 3, text: 'ayah three'),
      ];

      final List<InlineSpan> spans = await spansOf(tester, ayahs);
      final String all = spans
          .whereType<TextSpan>()
          .map((TextSpan s) => s.text ?? '')
          .join();

      expect(
        all.contains('۝'),
        isFalse,
        reason: 'a U+06DD reached the rendered span tree',
      );

      // One marker per ayah: three numbered medallions, not six glyphs.
      for (int n = 1; n <= 3; n++) {
        final String digits = AyahText.ayahNumberMarker(n);
        expect(
          RegExp(RegExp.escape(digits)).allMatches(all).length,
          1,
          reason: 'ayah $n marker appears more than once',
        );
      }
    });

    testWidgets('the ayah text itself is passed through verbatim', (
      WidgetTester tester,
    ) async {
      // Real text from the asset, with its Uthmani sukun (U+06E1). The marker
      // must not be glued onto it, normalised into it, or otherwise edited —
      // scripture is rendered exactly as loaded (CLAUDE.md A.2 rule 1).
      const String verbatim = 'ٱلۡحَمۡدُ لِلَّهِ رَبِّ ٱلۡعَٰلَمِينَ';
      final List<InlineSpan> spans = await spansOf(tester, <FlowingAyah>[
        const FlowingAyah(number: 2, text: verbatim),
      ]);

      final List<String> texts = spans
          .whereType<TextSpan>()
          .map((TextSpan s) => s.text ?? '')
          .toList();

      // The ayah occupies its own span, untouched, and the marker its own.
      expect(texts, contains(verbatim));
      expect(texts.any((String t) => t.trim() == '٢'), isTrue);
    });
  });
}
