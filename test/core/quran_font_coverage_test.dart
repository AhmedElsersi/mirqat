import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/theme/quran_font.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../quran_db_fixtures.dart';

/// Every codepoint mapped to a glyph by the font's `cmap` — formats 4 and 12,
/// the two a TrueType Arabic face carries. The same reading as
/// `tools/check_font_coverage.py`, so the two cannot disagree.
Set<int> cmapCodepoints(String path) {
  final ByteData d = ByteData.sublistView(File(path).readAsBytesSync());
  int u16(int o) => d.getUint16(o);
  int s16(int o) => d.getInt16(o);
  int u32(int o) => d.getUint32(o);

  int? cmap;
  final int tables = u16(4);
  for (int i = 0; i < tables; i++) {
    final int at = 12 + i * 16;
    final String tag = String.fromCharCodes(
      d.buffer.asUint8List(d.offsetInBytes + at, 4),
    );
    if (tag == 'cmap') cmap = u32(at + 8);
  }
  if (cmap == null) throw StateError('$path has no cmap');

  final Set<int> out = <int>{};
  final int subtables = u16(cmap + 2);
  for (int i = 0; i < subtables; i++) {
    final int sub = cmap + u32(cmap + 4 + i * 8 + 4);
    switch (u16(sub)) {
      case 4:
        final int segX2 = u16(sub + 6);
        final int seg = segX2 ~/ 2;
        final int ends = sub + 14;
        final int starts = ends + segX2 + 2;
        final int deltas = starts + segX2;
        final int ranges = deltas + segX2;
        for (int k = 0; k < seg; k++) {
          final int start = u16(starts + k * 2);
          final int end = u16(ends + k * 2);
          final int delta = s16(deltas + k * 2);
          final int range = u16(ranges + k * 2);
          for (int c = start; c <= end && c != 0xFFFF; c++) {
            int g;
            if (range == 0) {
              g = (c + delta) & 0xFFFF;
            } else {
              final int gi = ranges + k * 2 + range + (c - start) * 2;
              if (gi + 2 > d.lengthInBytes) continue;
              g = u16(gi);
              if (g != 0) g = (g + delta) & 0xFFFF;
            }
            if (g != 0) out.add(c);
          }
        }
      case 12:
        final int groups = u32(sub + 12);
        for (int k = 0; k < groups; k++) {
          final int at = sub + 16 + k * 12;
          for (int c = u32(at); c <= u32(at + 4); c++) {
            out.add(c);
          }
        }
    }
  }
  return out;
}

void main() {
  late Set<int> needed;

  setUpAll(() async {
    final Database db = await RepoQuranDatabase().open();
    needed = <int>{};
    for (final Map<String, Object?> row in await db.rawQuery(
      'SELECT text FROM ayahs UNION ALL SELECT text FROM words',
    )) {
      needed.addAll((row['text']! as String).runes.where((int c) => c != 0x20));
    }
  });

  test('the text has codepoints to check against', () {
    expect(needed.length, greaterThan(40));
  });

  // The bundled faces draw the text itself. The QPC V2 face draws a page
  // from glyph codes in that page's own font, fetched at run time; what it
  // draws when a font is missing is its bundled text face, checked here.
  for (final QuranFont font in <QuranFont>[
    for (final QuranFont f in QuranFont.values)
      if (f.assetPath != null) f,
  ]) {
    test('${font.name} has a glyph for every codepoint quran.db holds', () {
      final Set<int> missing = needed.difference(
        cmapCodepoints(font.assetPath!),
      );
      expect(
        missing.map((int c) => 'U+${c.toRadixString(16).toUpperCase()}'),
        isEmpty,
      );
    });

    test('${font.name} is declared in pubspec.yaml', () {
      expect(
        File('pubspec.yaml').readAsStringSync(),
        contains('- asset: ${font.assetPath}'),
      );
    });
  }

  test('a fetched face draws its fallback text in a bundled one', () {
    for (final QuranFont font in QuranFont.values) {
      expect(font.textFace.assetPath, isNotNull, reason: font.name);
    }
    expect(QuranFont.qpcV2.textFace, QuranFont.fallback);
    expect(QuranFont.fromStorage('qpc_v2'), QuranFont.qpcV2);
  });

  test('Amiri Quran is not offered, and this is why: it lacks a mark the '
      'text uses — in this encoding a mark of the KFGQPC script', () {
    const String amiri = 'assets/fonts/AmiriQuran.ttf';
    expect(
      QuranFont.values.map((QuranFont f) => f.assetPath),
      isNot(contains(amiri)),
    );
    expect(needed.difference(cmapCodepoints(amiri)), contains(0x065E));
  });

  test('a stored face no longer offered is the default, never an error', () {
    expect(QuranFont.fromStorage('hafs_v18'), QuranFont.hafsV18);
    expect(QuranFont.fromStorage('amiri'), QuranFont.fallback);
    expect(QuranFont.fromStorage(null), QuranFont.fallback);
    expect(QuranFont.fromStorage(7), QuranFont.fallback);
  });
}
