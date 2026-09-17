import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/constants/asset_paths.dart';
import 'package:mirqat/core/error/exceptions.dart';
import 'package:mirqat/core/error/failures.dart';
import 'package:mirqat/data/datasources/ayah_sequence_validator.dart';
import 'package:mirqat/data/datasources/quran_local_data_source.dart';
import 'package:mirqat/data/models/ayah.dart';
import 'package:mirqat/data/models/reciter.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:mirqat/data/repositories/quran_repository.dart';

import '../quran_db_fixtures.dart';

const String _goodReciters = '''
[{"id":"r","nameAr":"ق","nameEn":"R","audioMode":"per_ayah_files",
  "basePath":"assets/audio/r","bundled":true,"availableSurahs":[1],
  "hasIstiadhah":false}]
''';

const SurahDbRow _goodSurah = SurahDbRow(
  id: 1,
  ayahCount: 3,
  basmalaMode: 'first_ayah',
);

List<AyahDbRow> _ayahs(List<String> texts, {List<int>? numbers}) => <AyahDbRow>[
  for (int i = 0; i < texts.length; i++)
    AyahDbRow(1, numbers == null ? i + 1 : numbers[i], texts[i]),
];

QuranLocalDataSource _sourceWith({
  SurahDbRow surah = _goodSurah,
  List<AyahDbRow> ayahs = const <AyahDbRow>[],
  String? reciters = _goodReciters,
  String? timings,
}) => QuranLocalDataSourceImpl(
  FakeAssetReader(<String, String>{
    AssetPaths.recitersCatalog: ?reciters,
    AssetPaths.timingsForSurah('r', 1): ?timings,
  }),
  FixtureQuranDatabase(surahs: <SurahDbRow>[surah], ayahs: ayahs),
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
    test('rejects a surah holding fewer ayahs than its row declares', () async {
      final QuranLocalDataSource source = _sourceWith(
        ayahs: _ayahs(<String>['ب', 'ب']),
      );

      expect(
        await _messageFrom(() => source.getAyahs(1)),
        allOf(contains('missing ayah 3'), contains('contiguous 1..3')),
      );
    });

    test('rejects a surah holding more ayahs than its row declares', () async {
      final QuranLocalDataSource source = _sourceWith(
        ayahs: _ayahs(<String>['ب', 'ب', 'ب', 'ب']),
      );

      expect(
        await _messageFrom(() => source.getAyahs(1)),
        allOf(contains('ayah 4'), contains('beyond the ayahCount of 3')),
      );
    });

    test('rejects a duplicated ayah number', () async {
      final QuranLocalDataSource source = _sourceWith(
        ayahs: _ayahs(<String>['ب', 'ب', 'ب'], numbers: <int>[1, 2, 2]),
      );

      expect(
        await _messageFrom(() => source.getAyahs(1)),
        contains('lists ayah 2 more than once'),
      );
    });

    test('rejects a gap in the sequence', () async {
      final QuranLocalDataSource source = _sourceWith(
        ayahs: _ayahs(<String>['ب', 'ب'], numbers: <int>[1, 3]),
      );

      expect(
        await _messageFrom(() => source.getAyahs(1)),
        contains('missing ayah 2'),
      );
    });

    test('rejects ayahs out of order', () {
      // The loader asks the database for ayah order, so this is exercised
      // on the validator directly — it is the net if that query ever changes.
      const Surah surah = Surah(
        number: 1,
        nameAr: 'س',
        nameEn: 'Fixture',
        ayahCount: 3,
        revelationPlace: RevelationPlace.makkah,
        bismillahMode: BismillahMode.countedAsAyah1,
      );
      expect(
        () => validateAyahSequence(
          <Ayah>[
            const Ayah(surahNumber: 1, number: 1, text: 'ب'),
            const Ayah(surahNumber: 1, number: 3, text: 'ب'),
            const Ayah(surahNumber: 1, number: 2, text: 'ب'),
          ],
          surah: surah,
          path: 'fixture',
        ),
        throwsA(
          isA<CatalogValidationException>().having(
            (CatalogValidationException e) => e.message,
            'message',
            allOf(contains('out of order'), contains('position 2')),
          ),
        ),
      );
    });

    test('rejects empty ayah text rather than filling the gap', () async {
      final QuranLocalDataSource source = _sourceWith(
        ayahs: _ayahs(<String>['ب', '  ', 'ب']),
      );

      expect(
        await _messageFrom(() => source.getAyahs(1)),
        allOf(contains('empty text'), contains('never generated')),
      );
    });

    test('rejects text carrying a non-Arabic combining mark', () async {
      // A Latin combining acute (U+0301) would be silently mis-ordered by the
      // Arabic-scoped normalizer, so it is refused instead.
      final QuranLocalDataSource source = _sourceWith(
        ayahs: _ayahs(<String>['ب', 'b\u0301', 'ب']),
      );

      expect(
        await _messageFrom(() => source.getAyahs(1)),
        allOf(contains('outside the Arabic blocks'), contains('U+0062')),
      );
    });

    test('accepts NFD input and normalises it to NFC', () async {
      // Alef + maddah written as U+0627 U+0653 instead of U+0622.
      final QuranLocalDataSource source = _sourceWith(
        ayahs: _ayahs(<String>['\u0627\u0653', 'ب', 'ب']),
      );

      final List<Ayah> ayahs = await source.getAyahs(1);
      expect(ayahs.first.text, '\u0622');
      expect(ayahs.first.text.codeUnits, hasLength(1));
    });
  });

  group('catalog validation', () {
    test('rejects an unknown basmala_mode', () async {
      final QuranLocalDataSource source = _sourceWith(
        surah: const SurahDbRow(id: 1, ayahCount: 3, basmalaMode: 'sometimes'),
      );

      expect(
        await _messageFrom(() => source.getSurahs()),
        allOf(
          contains('Unknown basmala_mode "sometimes"'),
          contains('separate'),
        ),
      );
    });

    test('rejects a surah with no revelation place', () async {
      final QuranLocalDataSource source = _sourceWith(
        surah: const SurahDbRow(id: 1, ayahCount: 3, revelation: null),
      );

      expect(
        await _messageFrom(() => source.getSurahs()),
        contains('no revelation place'),
      );
    });

    test('maps every basmala_mode onto its BismillahMode', () async {
      final QuranLocalDataSource source = QuranLocalDataSourceImpl(
        FakeAssetReader(const <String, String>{}),
        FixtureQuranDatabase(
          surahs: const <SurahDbRow>[
            SurahDbRow(id: 1, ayahCount: 1, basmalaMode: 'first_ayah'),
            SurahDbRow(id: 2, ayahCount: 1, basmalaMode: 'separate'),
            SurahDbRow(id: 3, ayahCount: 1, basmalaMode: 'none'),
          ],
        ),
      );

      expect(
        (await source.getSurahs()).map((Surah s) => s.bismillahMode),
        <BismillahMode>[
          BismillahMode.countedAsAyah1,
          BismillahMode.separatePreamble,
          BismillahMode.none,
        ],
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

    test('rejects malformed reciter JSON', () async {
      final QuranLocalDataSource source = _sourceWith(reciters: '[{');

      expect(
        await _messageFrom(() => source.getReciters()),
        contains('Invalid JSON'),
      );
    });

    test('rejects a timings file that does not cover every ayah', () async {
      final QuranLocalDataSource source = _sourceWith(
        timings:
            '{"surah":1,"ayahs":['
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
      final QuranRepository repository = QuranRepositoryImpl(_sourceWith());

      final Either<Failure, List<Ayah>> result = await repository.getAyahs(1);

      expect(result.isLeft(), isTrue);
      result.fold((Failure f) {
        expect(f, isA<CatalogValidationFailure>());
        expect(f.message, contains('missing ayah 1'));
      }, (_) => fail('expected a Left'));
    });

    test('maps a missing asset onto AssetNotFoundFailure', () async {
      final QuranRepository repository = QuranRepositoryImpl(
        _sourceWith(reciters: null),
      );

      final Either<Failure, List<Reciter>> result = await repository
          .getReciters();

      expect(result.isLeft(), isTrue);
      result.fold(
        (Failure f) => expect(f, isA<AssetNotFoundFailure>()),
        (_) => fail('expected a Left'),
      );
    });

    test('rejects an ayah range beyond the surah', () async {
      final QuranRepository repository = QuranRepositoryImpl(
        _sourceWith(ayahs: _ayahs(<String>['ب', 'ب', 'ب'])),
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
        _sourceWith(ayahs: _ayahs(<String>['ب', 'ب', 'ب'])),
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
        _sourceWith(ayahs: _ayahs(<String>['ب', 'ت', 'ث'])),
      );

      final Either<Failure, List<Ayah>> result = await repository.getAyahRange(
        1,
        startAyah: 2,
        endAyah: 3,
      );

      expect(result.getOrElse(() => <Ayah>[]).map((Ayah a) => a.number), <int>[
        2,
        3,
      ]);
    });
  });
}
