import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahfiz/core/constants/asset_paths.dart';
import 'package:tahfiz/core/error/exceptions.dart';
import 'package:tahfiz/core/error/failures.dart';
import 'package:tahfiz/data/datasources/asset_reader.dart';
import 'package:tahfiz/data/datasources/quran_local_data_source.dart';
import 'package:tahfiz/data/models/ayah.dart';
import 'package:tahfiz/data/repositories/quran_repository.dart';

/// Serves whatever JSON a test hands it, so deliberately corrupted catalogs
/// can be pushed through the real loaders.
class FakeAssetReader implements AssetReader {
  FakeAssetReader(this.files);

  final Map<String, String> files;

  @override
  Future<String> loadString(String path) async {
    final String? content = files[path];
    if (content == null) {
      throw AssetNotFoundException(path, 'Fixture has no asset at "$path".');
    }
    return content;
  }
}

const String _goodSurahs = '''
[{"number":1,"nameAr":"الفاتحة","nameEn":"Al-Fatiha","ayahCount":3,
  "revelationPlace":"makkah","bismillahMode":"counted_as_ayah_1"}]
''';

const String _goodReciters = '''
[{"id":"r","nameAr":"ق","nameEn":"R","audioMode":"per_ayah_files",
  "basePath":"assets/audio/r","bundled":true,"availableSurahs":[1],
  "hasIstiadhah":false}]
''';

String _ayahFile(String ayahsJson, {int surah = 1}) =>
    '{"surah":$surah,"script":"uthmani","source":"fixture","ayahs":$ayahsJson}';

QuranLocalDataSource _sourceWith({
  String surahs = _goodSurahs,
  String? ayahs,
  String reciters = _goodReciters,
  String? timings,
}) => QuranLocalDataSourceImpl(
  FakeAssetReader(<String, String>{
    AssetPaths.surahsCatalog: surahs,
    AssetPaths.recitersCatalog: reciters,
    AssetPaths.ayahsForSurah(1): ?ayahs,
    AssetPaths.timingsForSurah('r', 1): ?timings,
  }),
);

Future<String> _messageFrom(Future<void> Function() body) async {
  try {
    await body();
  } on AppException catch (e) {
    return e.message;
  }
  fail('expected the loader to reject this fixture, but it succeeded');
}

void main() {
  group('ayah sequence validation', () {
    test('rejects a file holding fewer ayahs than the catalog declares',
        () async {
      final QuranLocalDataSource source = _sourceWith(
        ayahs: _ayahFile('[{"number":1,"text":"ب"},{"number":2,"text":"ب"}]'),
      );

      expect(
        await _messageFrom(() => source.getAyahs(1)),
        allOf(contains('missing ayah 3'), contains('contiguous 1..3')),
      );
    });

    test('rejects a file holding more ayahs than the catalog declares',
        () async {
      final QuranLocalDataSource source = _sourceWith(
        ayahs: _ayahFile(
          '[{"number":1,"text":"ب"},{"number":2,"text":"ب"},'
          '{"number":3,"text":"ب"},{"number":4,"text":"ب"}]',
        ),
      );

      expect(
        await _messageFrom(() => source.getAyahs(1)),
        allOf(contains('ayah 4'), contains('beyond the ayahCount of 3')),
      );
    });

    test('rejects a duplicated ayah number', () async {
      final QuranLocalDataSource source = _sourceWith(
        ayahs: _ayahFile(
          '[{"number":1,"text":"ب"},{"number":2,"text":"ب"},'
          '{"number":2,"text":"ب"}]',
        ),
      );

      expect(
        await _messageFrom(() => source.getAyahs(1)),
        contains('lists ayah 2 more than once'),
      );
    });

    test('rejects a gap in the sequence', () async {
      final QuranLocalDataSource source = _sourceWith(
        ayahs: _ayahFile(
          '[{"number":1,"text":"ب"},{"number":3,"text":"ب"}]',
        ),
      );

      expect(
        await _messageFrom(() => source.getAyahs(1)),
        contains('missing ayah 2'),
      );
    });

    test('rejects ayahs listed out of order', () async {
      final QuranLocalDataSource source = _sourceWith(
        ayahs: _ayahFile(
          '[{"number":1,"text":"ب"},{"number":3,"text":"ب"},'
          '{"number":2,"text":"ب"}]',
        ),
      );

      expect(
        await _messageFrom(() => source.getAyahs(1)),
        allOf(contains('out of order'), contains('position 2')),
      );
    });

    test('rejects empty ayah text rather than filling the gap', () async {
      final QuranLocalDataSource source = _sourceWith(
        ayahs: _ayahFile(
          '[{"number":1,"text":"ب"},{"number":2,"text":"  "},'
          '{"number":3,"text":"ب"}]',
        ),
      );

      expect(
        await _messageFrom(() => source.getAyahs(1)),
        allOf(contains('empty "text"'), contains('never generated')),
      );
    });

    test('rejects text carrying a non-Arabic combining mark', () async {
      // A Latin combining acute (U+0301) would be silently mis-ordered by the
      // Arabic-scoped normalizer, so it is refused instead.
      final QuranLocalDataSource source = _sourceWith(
        ayahs: _ayahFile(
          '[{"number":1,"text":"ب"},{"number":2,"text":"b\\u0301"},'
          '{"number":3,"text":"ب"}]',
        ),
      );

      expect(
        await _messageFrom(() => source.getAyahs(1)),
        allOf(contains('outside the Arabic blocks'), contains('U+0062')),
      );
    });

    test('rejects an ayah file whose surah number disagrees', () async {
      final QuranLocalDataSource source = _sourceWith(
        ayahs: _ayahFile('[]', surah: 2),
      );

      expect(
        await _messageFrom(() => source.getAyahs(1)),
        contains('declares surah 2 but was loaded for surah 1'),
      );
    });

    test('accepts NFD input and normalises it to NFC', () async {
      // Same ayah, alef + maddah written as U+0627 U+0653 instead of U+0622.
      final QuranLocalDataSource source = _sourceWith(
        ayahs: _ayahFile(
          '[{"number":1,"text":"\\u0627\\u0653"},{"number":2,"text":"ب"},'
          '{"number":3,"text":"ب"}]',
        ),
      );

      final List<Ayah> ayahs = await source.getAyahs(1);
      expect(ayahs.first.text, 'آ');
      expect(ayahs.first.text.codeUnits, hasLength(1));
    });
  });

  group('catalog validation', () {
    test('rejects an unknown bismillahMode', () async {
      final QuranLocalDataSource source = _sourceWith(
        surahs: _goodSurahs.replaceAll('counted_as_ayah_1', 'sometimes'),
      );

      expect(
        await _messageFrom(() => source.getSurahs()),
        allOf(
          contains('Unknown bismillahMode "sometimes"'),
          contains('separate_preamble'),
        ),
      );
    });

    test('rejects an unknown audioMode', () async {
      final QuranLocalDataSource source = _sourceWith(
        reciters: _goodReciters.replaceAll('per_ayah_files', 'streaming'),
      );

      expect(
        await _messageFrom(() => source.getReciters()),
        allOf(
          contains('Unknown audioMode "streaming"'),
          contains('single_file_with_timings'),
        ),
      );
    });

    test('rejects a duplicated surah number', () async {
      final QuranLocalDataSource source = _sourceWith(
        surahs: '[${_goodSurahs.substring(1, _goodSurahs.length - 2)},'
            '${_goodSurahs.substring(1, _goodSurahs.length - 2)}]',
      );

      expect(
        await _messageFrom(() => source.getSurahs()),
        contains('lists surah 1 more than once'),
      );
    });

    test('rejects malformed JSON', () async {
      final QuranLocalDataSource source = _sourceWith(surahs: '[{');

      expect(
        await _messageFrom(() => source.getSurahs()),
        contains('Invalid JSON'),
      );
    });

    test('rejects a timings file that does not cover every ayah', () async {
      final QuranLocalDataSource source = _sourceWith(
        timings: '{"surah":1,"ayahs":['
            '{"number":1,"startMs":0,"endMs":100},'
            '{"number":2,"startMs":100,"endMs":200}]}',
      );

      expect(
        await _messageFrom(
          () => source.getTimings(reciterId: 'r', surahNumber: 1),
        ),
        contains('missing ayah 3 of 3'),
      );
    });

    test('rejects a timing window that ends before it starts', () async {
      final QuranLocalDataSource source = _sourceWith(
        timings: '{"surah":1,"ayahs":[{"number":1,"startMs":500,"endMs":100}]}',
      );

      expect(
        await _messageFrom(
          () => source.getTimings(reciterId: 'r', surahNumber: 1),
        ),
        contains('empty or negative window'),
      );
    });
  });

  group('repository', () {
    test('maps a validation failure onto the Left side', () async {
      final QuranRepository repository = QuranRepositoryImpl(
        _sourceWith(ayahs: _ayahFile('[]')),
      );

      final Either<Failure, List<Ayah>> result = await repository.getAyahs(1);

      expect(result.isLeft(), isTrue);
      result.fold(
        (Failure f) {
          expect(f, isA<CatalogValidationFailure>());
          expect(f.message, contains('missing ayah 1'));
        },
        (_) => fail('expected a Left'),
      );
    });

    test('maps a missing asset onto AssetNotFoundFailure', () async {
      final QuranRepository repository = QuranRepositoryImpl(_sourceWith());

      final Either<Failure, List<Ayah>> result = await repository.getAyahs(1);

      expect(result.isLeft(), isTrue);
      result.fold(
        (Failure f) => expect(f, isA<AssetNotFoundFailure>()),
        (_) => fail('expected a Left'),
      );
    });

    test('rejects an ayah range beyond the surah', () async {
      final QuranRepository repository = QuranRepositoryImpl(
        _sourceWith(
          ayahs: _ayahFile(
            '[{"number":1,"text":"ب"},{"number":2,"text":"ب"},'
            '{"number":3,"text":"ب"}]',
          ),
        ),
      );

      final Either<Failure, List<Ayah>> result = await repository.getAyahRange(
        1,
        startAyah: 1,
        endAyah: 9,
      );

      expect(result.isLeft(), isTrue);
      result.fold(
        (Failure f) => expect(f.message, contains('which has 3 ayahs')),
        (_) => fail('expected a Left'),
      );
    });

    test('rejects an inverted ayah range', () async {
      final QuranRepository repository = QuranRepositoryImpl(
        _sourceWith(
          ayahs: _ayahFile(
            '[{"number":1,"text":"ب"},{"number":2,"text":"ب"},'
            '{"number":3,"text":"ب"}]',
          ),
        ),
      );

      final Either<Failure, List<Ayah>> result = await repository.getAyahRange(
        1,
        startAyah: 3,
        endAyah: 2,
      );

      expect(result.isLeft(), isTrue);
      result.fold(
        (Failure f) => expect(f.message, contains('inverted')),
        (_) => fail('expected a Left'),
      );
    });

    test('returns the requested slice on the Right side', () async {
      final QuranRepository repository = QuranRepositoryImpl(
        _sourceWith(
          ayahs: _ayahFile(
            '[{"number":1,"text":"ب"},{"number":2,"text":"ت"},'
            '{"number":3,"text":"ث"}]',
          ),
        ),
      );

      final Either<Failure, List<Ayah>> result = await repository.getAyahRange(
        1,
        startAyah: 2,
        endAyah: 3,
      );

      expect(
        result.getOrElse(() => <Ayah>[]).map((Ayah a) => a.number),
        <int>[2, 3],
      );
    });
  });
}
