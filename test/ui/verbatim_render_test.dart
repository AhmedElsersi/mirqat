import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/widgets/ayah_text.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../app_harness.dart';
import '../quran_db_fixtures.dart';

/// What the renderer is handed is what quran.db holds — checked on the real
/// reader screen, not just at the repository.
void main() {
  late AppHarness harness;
  late Surah surah;
  late List<AyahDbRow> stored;
  late String firstAyahOfCatalog;

  setUpAll(() async {
    final Database db = await RepoQuranDatabase().open();
    final List<Surah> catalog = (await db.query(
      'surahs',
      orderBy: 'id',
    )).map(Surah.fromDbRow).toList();

    // The first surah with a tatweel-seated mark and an unnumbered bismillah,
    // chosen by content rather than by number.
    final Set<int> seated = <int>{
      for (final Map<String, Object?> r in await db.rawQuery(
        "SELECT DISTINCT surah FROM ayahs WHERE instr(text, char(1600)) > 0",
      ))
        r['surah']! as int,
    };
    surah = catalog.firstWhere(
      (Surah s) =>
          seated.contains(s.number) &&
          s.bismillahMode == BismillahMode.separatePreamble,
    );

    stored = <AyahDbRow>[
      for (final Map<String, Object?> r in await db.query(
        'ayahs',
        where: 'surah = ?',
        whereArgs: <int>[surah.number],
        orderBy: 'ayah',
      ))
        AyahDbRow(r['surah']! as int, r['ayah']! as int, r['text']! as String),
    ];

    final Surah bismillahSource = catalog.firstWhere(
      (Surah s) => s.bismillahMode == BismillahMode.countedAsAyah1,
    );
    firstAyahOfCatalog =
        (await db.query(
              'ayahs',
              columns: <String>['text'],
              where: 'surah = ? AND ayah = 1',
              whereArgs: <int>[bismillahSource.number],
            )).single['text']!
            as String;
  });

  setUp(() async => harness = await AppHarness.start());
  tearDown(() async => harness.stop());
  tearDownAll(AppHarness.disposeAll);

  testWidgets('every ayah span the reader renders equals its quran.db row, '
      'tatweel-seated marks included', (WidgetTester tester) async {
    expect(
      stored.where((AyahDbRow r) => r.text.contains('ـ')),
      isNotEmpty,
      reason: 'the sample must include ayahs with a tatweel-seated mark',
    );

    await harness.pumpApp(tester);
    await AppHarness.tapAndSettle(tester, find.text(surah.nameAr));

    final List<String> rendered = <String>[
      for (final RichText rich in tester.widgetList<RichText>(
        find.descendant(
          of: find.byType(AyahText),
          matching: find.byType(RichText),
        ),
      ))
        ..._leafTexts(rich.text),
    ];

    for (final AyahDbRow row in stored) {
      expect(
        rendered.where((String t) => _sameCodeUnits(t, row.text)),
        isNotEmpty,
        reason:
            '${row.surah}:${row.ayah} is not rendered byte-for-byte as stored',
      );
    }

    // The bismillah header is scripture too, and comes from the same place.
    expect(
      rendered.where((String t) => _sameCodeUnits(t, firstAyahOfCatalog)),
      isNotEmpty,
      reason: 'the bismillah header is not rendered as stored',
    );
  });
}

List<String> _leafTexts(InlineSpan span) {
  final List<String> out = <String>[];
  span.visitChildren((InlineSpan child) {
    if (child is TextSpan && child.text != null && child.text!.isNotEmpty) {
      out.add(child.text!);
    }
    return true;
  });
  return out;
}

bool _sameCodeUnits(String a, String b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a.codeUnitAt(i) != b.codeUnitAt(i)) return false;
  }
  return true;
}
