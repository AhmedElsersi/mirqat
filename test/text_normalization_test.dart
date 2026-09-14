import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/constants/asset_paths.dart';
import 'package:mirqat/core/extensions/arabic_normalization_tables.dart';
import 'package:mirqat/core/extensions/arabic_text_extensions.dart';
import 'package:mirqat/data/datasources/asset_reader.dart';
import 'package:mirqat/data/datasources/bundle_asset_reader.dart';
import 'package:mirqat/data/datasources/quran_local_data_source.dart';
import 'package:mirqat/data/models/ayah.dart';
import 'package:mirqat/data/models/surah.dart';

/// Encoding variance in ayah text, at the loader boundary.
///
/// Two halves, and the second is the one that matters. Asserting the shipped
/// files are clean today only records today. Asserting the loader *levels*
/// input variance means an edition that arrives tomorrow in NFD, or carrying
/// tatweel, compares equal to what is already stored rather than silently
/// never matching — a failure that renders identically on screen and shows up
/// only as search and highlighting quietly not working.
///
/// No Quranic text is written in this file. Every fixture is derived from the
/// shipped bytes by a mechanical transform of their *encoding*; the letters,
/// the diacritics and their order are the asset's own.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AssetReader bundle;
  late QuranLocalDataSource loader;

  setUp(() {
    bundle = BundleAssetReader();
    loader = QuranLocalDataSourceImpl(bundle);
  });

  group('what ships', () {
    test('every ayah equals its own NFC form', () async {
      for (final Surah surah in await loader.getSurahs()) {
        for (final String text in await _shippedTexts(bundle, surah.number)) {
          expect(
            text,
            text.toArabicNfc(),
            reason:
                'surah ${surah.number} ships an ayah that is not in NFC. It '
                'will render correctly and compare unequal to the same ayah '
                'from any other source.',
          );
        }
      }
    });

    test('no ayah carries U+0640 ARABIC TATWEEL', () async {
      for (final Surah surah in await loader.getSurahs()) {
        final List<String> texts = await _shippedTexts(bundle, surah.number);
        for (int i = 0; i < texts.length; i++) {
          expect(
            texts[i].contains('ـ'),
            isFalse,
            reason:
                'surah ${surah.number} ayah ${i + 1} carries a tatweel at '
                'offset ${texts[i].indexOf('ـ')} — typographic filler '
                'from another edition, with no sound and no meaning.',
          );
        }
      }
    });
  });

  group('what the loader repairs', () {
    test('an ayah file in NFD loads equal to the NFC form', () async {
      for (final Surah surah in await loader.getSurahs()) {
        final List<Ayah> shipped = await loader.getAyahs(surah.number);
        final List<Ayah> reloaded = await _loadTransformed(
          bundle,
          surah.number,
          _toNfd,
        );

        expect(
          reloaded.map((Ayah a) => a.text),
          shipped.map((Ayah a) => a.text),
          reason:
              'surah ${surah.number} decomposed to NFD did not come back '
              'equal to the composed form. Anything keyed on ayah text would '
              'miss across the two encodings.',
        );
      }
    });

    test('the NFD fixture is a real one, not an identity transform', () async {
      final List<Surah> surahs = await loader.getSurahs();
      int decomposed = 0;
      for (final Surah surah in surahs) {
        for (final String text in await _shippedTexts(bundle, surah.number)) {
          if (_toNfd(text) != text) decomposed++;
        }
      }
      expect(
        decomposed,
        greaterThan(0),
        reason:
            'no shipped ayah changed under decomposition, so the test above '
            'proved nothing. Check the decomposition table.',
      );
    });

    test('an ayah file carrying tatweel loads equal to the same text '
        'without it', () async {
      for (final Surah surah in await loader.getSurahs()) {
        final List<Ayah> shipped = await loader.getAyahs(surah.number);
        final List<Ayah> reloaded = await _loadTransformed(
          bundle,
          surah.number,
          _injectTatweel,
        );

        expect(
          reloaded.map((Ayah a) => a.text),
          shipped.map((Ayah a) => a.text),
          reason:
              'surah ${surah.number} with tatweel injected did not come back '
              'equal to the shipped text. The loader must drop U+0640 on read.',
        );
      }
    });

    test('the tatweel fixture actually carries tatweel', () async {
      final List<String> texts = await _shippedTexts(
        bundle,
        (await loader.getSurahs()).first.number,
      );
      expect(_injectTatweel(texts.first).contains('ـ'), isTrue);
    });

    test('both repairs at once still land on the shipped form', () async {
      for (final Surah surah in await loader.getSurahs()) {
        final List<Ayah> shipped = await loader.getAyahs(surah.number);
        final List<Ayah> reloaded = await _loadTransformed(
          bundle,
          surah.number,
          (String s) => _injectTatweel(_toNfd(s)),
        );
        expect(reloaded.map((Ayah a) => a.text), shipped.map((Ayah a) => a.text));
      }
    });
  });

  test('the repair is a levelling, never an edit', () async {
    // Nothing is added, replaced or re-diacritized. The shipped files are
    // already canonical, so what the loader returns must be the asset's own
    // codepoints, rune for rune — the normalizer is a no-op on clean input.
    for (final Surah surah in await loader.getSurahs()) {
      final List<Ayah> loaded = await loader.getAyahs(surah.number);
      final List<String> shipped = await _shippedTexts(bundle, surah.number);

      for (int i = 0; i < loaded.length; i++) {
        expect(
          loaded[i].text.runes.toList(),
          shipped[i].runes.toList(),
          reason:
              'surah ${surah.number} ayah ${loaded[i].number} came back from '
              'the loader with different codepoints than the asset holds. The '
              'loader levels encoding variance; it must never change the text.',
        );
      }
    }
  });
}

/// The `text` values exactly as the asset holds them, before the loader
/// touches anything.
Future<List<String>> _shippedTexts(AssetReader reader, int surahNumber) async {
  final Map<String, dynamic> doc =
      jsonDecode(await reader.loadString(AssetPaths.ayahsForSurah(surahNumber)))
          as Map<String, dynamic>;
  return <String>[
    for (final dynamic a in doc['ayahs'] as List<dynamic>)
      (a as Map<String, dynamic>)['text'] as String,
  ];
}

/// Runs the real loader over the real ayah file with every `text` put through
/// [transform] — the file on disk is never touched.
Future<List<Ayah>> _loadTransformed(
  AssetReader reader,
  int surahNumber,
  String Function(String) transform,
) async {
  final String path = AssetPaths.ayahsForSurah(surahNumber);
  final Map<String, dynamic> doc =
      jsonDecode(await reader.loadString(path)) as Map<String, dynamic>;

  final List<dynamic> ayahs = doc['ayahs'] as List<dynamic>;
  doc['ayahs'] = <Map<String, dynamic>>[
    for (final dynamic a in ayahs)
      <String, dynamic>{
        ...(a as Map<String, dynamic>),
        'text': transform(a['text'] as String),
      },
  ];

  final QuranLocalDataSource patched = QuranLocalDataSourceImpl(
    _PatchedReader(reader, <String, String>{path: jsonEncode(doc)}),
  );
  return patched.getAyahs(surahNumber);
}

/// Canonical decomposition — NFD — using the app's own generated table, so a
/// composed character in the asset arrives at the loader taken apart.
String _toNfd(String text) {
  final StringBuffer out = StringBuffer();
  for (final int cp in text.runes) {
    final List<int>? parts = arabicCanonicalDecomposition[cp];
    if (parts == null) {
      out.writeCharCode(cp);
    } else {
      for (final int part in parts) {
        out.writeCharCode(part);
      }
    }
  }
  return out.toString();
}

/// Sprinkles U+0640 through the text the way a justified edition does.
///
/// Position is deliberately arbitrary — including between a letter and its
/// mark — because the loader must strip the tatweel *before* it composes, or a
/// mark it separated would fail to rejoin its base.
String _injectTatweel(String text) {
  final StringBuffer out = StringBuffer();
  int i = 0;
  for (final int cp in text.runes) {
    out.writeCharCode(cp);
    if (i.isEven) out.write('ـ');
    i++;
  }
  return out.toString();
}

class _PatchedReader implements AssetReader {
  _PatchedReader(this._inner, this._patches);

  final AssetReader _inner;
  final Map<String, String> _patches;

  @override
  Future<String> loadString(String path) async =>
      _patches[path] ?? await _inner.loadString(path);
}
