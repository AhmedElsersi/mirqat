import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/error/exceptions.dart';
import 'package:mirqat/core/state/load_status.dart';
import 'package:mirqat/data/datasources/asset_reader.dart';
import 'package:mirqat/data/datasources/quran_database.dart';
import 'package:mirqat/data/datasources/quran_local_data_source.dart';
import 'package:mirqat/data/datasources/quran_pages_local_data_source.dart';
import 'package:mirqat/data/models/mutashabihat.dart';
import 'package:mirqat/data/models/word.dart';
import 'package:mirqat/data/repositories/mutashabihat_repository.dart';
import 'package:mirqat/data/repositories/quran_pages_repository.dart';
import 'package:mirqat/data/repositories/quran_repository.dart';
import 'package:mirqat/domain/entities/ayah_ref.dart';
import 'package:mirqat/features/similar/cubit/similar_cubit.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../app_harness.dart' show FileAssetReader;

Map<String, Object?> data(List<Map<String, Object?>> phrases) =>
    <String, Object?>{'schemaVersion': 1, 'source': 't', 'phrases': phrases};

/// Two phrases: a long one shared by 2:62, 2:112 and 5:69, and a short one
/// shared by 2:62 and 2:23.
final Map<String, Object?> sample = data(<Map<String, Object?>>[
  <String, Object?>{
    'id': 1,
    'ayahs': <List<int>>[
      <int>[2, 62, 19, 24],
      <int>[2, 112, 12, 17],
      <int>[5, 69, 15, 20],
    ],
  },
  <String, Object?>{
    'id': 2,
    'ayahs': <List<int>>[
      <int>[2, 23, 1, 2],
      <int>[2, 62, 1, 2],
    ],
  },
]);

class _Assets implements AssetReader {
  _Assets(this.files);

  final Map<String, String> files;

  @override
  Future<String> loadString(String path) async =>
      files[path] ?? (throw AssetNotFoundException(path, 'absent'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the index', () {
    final MutashabihatIndex index = MutashabihatIndex.fromJson(sample);

    test(
      'the most alike first: the longest phrase shared, then mushaf order',
      () {
        expect(
          index.similarTo(const AyahRef(2, 62)).map((SimilarAyah s) => s.ref),
          <AyahRef>[
            const AyahRef(2, 112),
            const AyahRef(5, 69),
            const AyahRef(2, 23),
          ],
        );
      },
    );

    test('says where the shared words fall, on both sides', () {
      final SimilarAyah s = index.similarTo(const AyahRef(2, 112)).first;
      expect(s.ref, const AyahRef(2, 62));
      expect(s.here.single.fromWord, 12);
      expect(s.there.single.fromWord, 19);
      expect(s.longest, 6);
    });

    test('an ayah never resembles itself', () {
      for (final SimilarAyah s in index.similarTo(const AyahRef(2, 62))) {
        expect(s.ref, isNot(const AyahRef(2, 62)));
      }
    });

    test('a file of another schema, or none, reads as nothing', () {
      expect(MutashabihatIndex.fromJson(null).isEmpty, isTrue);
      expect(
        MutashabihatIndex.fromJson(<String, Object?>{
          ...sample,
          'schemaVersion': 2,
        }).isEmpty,
        isTrue,
      );
    });

    test(
      'a malformed row is skipped; a phrase left in one ayah is dropped',
      () {
        final MutashabihatIndex i = MutashabihatIndex.fromJson(
          data(<Map<String, Object?>>[
            <String, Object?>{
              'id': 3,
              'ayahs': <Object?>[
                <int>[2, 62, 5, 2],
                <Object?>[2, 'x', 1, 2],
                <int>[2, 23, 1, 2],
              ],
            },
            <String, Object?>{'id': 'four', 'ayahs': <Object?>[]},
          ]),
        );
        expect(i.isEmpty, isTrue);
      },
    );
  });

  group('the repository', () {
    test('no data imported yet: empty, and the feature hides', () async {
      final MutashabihatRepository repo = MutashabihatRepository(
        _Assets(<String, String>{}),
      );
      expect((await repo.index()).isEmpty, isTrue);
    });

    test('a file that is not JSON: empty, never an error', () async {
      final MutashabihatRepository repo = MutashabihatRepository(
        _Assets(<String, String>{'assets/data/mutashabihat.json': '<html>'}),
      );
      expect((await repo.index()).isEmpty, isTrue);
    });

    test('read once and kept', () async {
      final MutashabihatRepository repo = MutashabihatRepository(
        _Assets(<String, String>{
          'assets/data/mutashabihat.json': jsonEncode(sample),
        }),
      );
      expect(identical(await repo.index(), await repo.index()), isTrue);
    });
  });

  group('the comparison, over the real quran.db', () {
    late Directory dir;
    late SimilarCubit cubit;

    setUp(() {
      sqfliteFfiInit();
      dir = Directory.systemTemp.createTempSync('similar_test');
      final QuranDatabase db = QuranDatabase(
        factory: databaseFactoryFfi,
        resolveStorageDirectory: () async => dir,
      );
      cubit = SimilarCubit(
        mutashabihatRepository: MutashabihatRepository(
          _Assets(<String, String>{
            'assets/data/mutashabihat.json': jsonEncode(sample),
          }),
        ),
        quranRepository: QuranRepositoryImpl(
          QuranLocalDataSourceImpl(const FileAssetReader(), db),
        ),
        pagesRepository: QuranPagesRepositoryImpl(
          QuranPagesLocalDataSourceImpl(db),
        ),
      );
    });

    tearDown(() async {
      await cubit.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('each ayah with its own words, the shared ones marked', () async {
      await cubit.load(const AyahRef(2, 112));
      expect(cubit.state.status, LoadStatus.ready);

      final ComparedAyah target = cubit.state.target!;
      expect(target.words.last.isMarker, isTrue);
      final List<int> shared = <int>[
        for (final Word w in target.words)
          if (target.isShared(w)) w.position,
      ];
      expect(shared, <int>[12, 13, 14, 15, 16, 17]);

      expect(cubit.state.similar.map((ComparedAyah c) => c.ref), <AyahRef>[
        const AyahRef(2, 62),
        const AyahRef(5, 69),
      ]);
      final ComparedAyah first = cubit.state.similar.first;
      expect(
        <int>[
          for (final Word w in first.words)
            if (first.isShared(w)) w.position,
        ],
        <int>[19, 20, 21, 22, 23, 24],
      );
    });

    test('the words are quran.db\'s own, byte for byte', () async {
      await cubit.load(const AyahRef(2, 112));
      final Database raw = await databaseFactoryFfi.openDatabase(
        File('assets/data/quran.db').absolute.path,
        options: OpenDatabaseOptions(readOnly: true),
      );
      final List<Map<String, Object?>> rows = await raw.query(
        'words',
        where: 'surah = 2 AND ayah = 112',
        orderBy: 'id',
      );
      await raw.close();
      expect(
        cubit.state.target!.words.map((Word w) => w.text),
        rows.map((Map<String, Object?> r) => r['text']),
      );
    });

    test(
      'an ayah with no similar ones shows itself and nothing else',
      () async {
        await cubit.load(const AyahRef(1, 1));
        expect(cubit.state.status, LoadStatus.ready);
        expect(cubit.state.similar, isEmpty);
      },
    );
  });
}
