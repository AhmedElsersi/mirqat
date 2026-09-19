import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/admin/services/recitation_weight.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The weights are read off the real text, so they are tested on the real
/// text: `assets/data/quran.db`, opened read-only.
void main() {
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(
      // Absolute: the ffi factory resolves a relative path under .dart_tool.
      File('assets/data/quran.db').absolute.path,
      options: OpenDatabaseOptions(readOnly: true),
    );
  });
  tearDownAll(() => db.close());

  Future<String> ayah(int surah, int number) async =>
      (await db.query(
            'ayahs',
            columns: <String>['text'],
            where: 'surah = ? AND ayah = ?',
            whereArgs: <Object>[surah, number],
          )).single['text']!
          as String;

  test('letter names outweigh the same letters inside a word', () async {
    // Five characters, about eleven seconds. Counted as five letters, the cut
    // after it lands ten seconds early and ayah 2 is left a fragment.
    final int muqattaat = recitationWeight(await ayah(19, 1));
    expect(muqattaat, greaterThanOrEqualTo(30));

    // But a letter name is only long when the text says it is held. `طه` has
    // no maddah: two names, two seconds. Weighting it like `كٓهيعٓصٓ` flagged a
    // correct 2.08s clip as a fragment of a five-second ayah.
    expect(recitationWeight(await ayah(20, 1)), lessThan(10));
    expect(
      recitationWeight(
        await ayah(50, 1).then((String t) => t.split(' ').first),
      ),
      greaterThan(recitationWeight(await ayah(20, 1))),
      reason: 'قٓ is one held letter and outlasts both of طه',
    );

    // 2:1 is three characters and outweighs an ordinary short ayah.
    expect(
      recitationWeight(await ayah(2, 1)),
      greaterThan(recitationWeight(await ayah(112, 3))),
    );
  });

  test('exactly the surahs that open with letter names are found, and no '
      'surah number is involved in finding them', () async {
    final List<Map<String, Object?>> rows = await db.query(
      'ayahs',
      columns: <String>['surah', 'text'],
      where: 'ayah = 1',
      orderBy: 'surah',
    );

    // A first word with letters but no vowel marks is what identifies them.
    final List<int> found = <int>[
      for (final Map<String, Object?> row in rows)
        if (_opensWithLetterNames(row['text']! as String)) row['surah']! as int,
    ];

    expect(found, <int>[
      2, 3, 7, 10, 11, 12, 13, 14, 15, 19, 20, 26, 27, 28, 29, 30, 31, 32, //
      36, 38, 40, 41, 42, 43, 44, 45, 46, 50, 68,
    ]);
  });

  test('a held vowel adds length; ordinary text is its letters', () async {
    final String text = await ayah(1, 7);
    final int letters = text.runes
        .where((int r) => r >= 0x0621 && r <= 0x064A)
        .length;
    final int maddahs = text.runes.where((int r) => r == 0x0653).length;

    expect(maddahs, greaterThan(0), reason: '1:7 holds a madd in الضآلين');
    expect(recitationWeight(text), letters + 3 * maddahs);
  });

  test('the text is only read', () async {
    final String before = await ayah(19, 1);
    recitationWeight(before);
    expect(await ayah(19, 1), before);
    expect(recitationWeight(''), 0);
    expect(recitationWeight('   '), 0);
  });
}

bool _opensWithLetterNames(String text) {
  final String first = text.trim().split(RegExp(r'\s+')).first;
  final bool hasLetters = first.runes.any(
    (int r) => r >= 0x0621 && r <= 0x064A,
  );
  final bool vowelled = first.runes.any((int r) => r >= 0x064B && r <= 0x0652);
  return hasLetters && !vowelled;
}
