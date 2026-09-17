import 'dart:io';

import 'package:mirqat/core/constants/asset_paths.dart';
import 'package:mirqat/core/error/exceptions.dart';
import 'package:mirqat/data/datasources/asset_reader.dart';
import 'package:mirqat/data/datasources/quran_database_opener.dart';
import 'package:mirqat/data/datasources/quran_local_data_source.dart';
import 'package:mirqat/data/repositories/quran_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _ffiReady = false;

void _ensureFfi() {
  if (_ffiReady) return;
  sqfliteFfiInit();
  _ffiReady = true;
}

/// The repo's shipped `quran.db`, opened in place and read-only — no copy, no
/// bundle, no path_provider.
class RepoQuranDatabase implements QuranDatabaseOpener {
  Future<Database>? _opening;

  @override
  Future<Database> open() {
    _ensureFfi();
    return _opening ??= databaseFactoryFfi.openDatabase(
      // Absolute: a relative path resolves against sqflite's own databases
      // directory, not the repo.
      File(AssetPaths.quranDatabase).absolute.path,
      options: OpenDatabaseOptions(readOnly: true),
    );
  }
}

/// One `surahs` row for [FixtureQuranDatabase].
class SurahDbRow {
  const SurahDbRow({
    required this.id,
    required this.ayahCount,
    this.nameAr = 'س',
    this.nameTranslit = 'Fixture',
    this.revelation = 'makkah',
    this.basmalaMode = 'separate',
  });

  final int id;
  final int ayahCount;
  final String nameAr;
  final String nameTranslit;
  final String? revelation;
  final String basmalaMode;
}

/// One `ayahs` row for [FixtureQuranDatabase].
class AyahDbRow {
  const AyahDbRow(this.surah, this.ayah, this.text);

  final int surah;
  final int ayah;
  final String text;
}

/// A throwaway in-memory database in `quran.db`'s shape, holding exactly the
/// rows a test hands it — so a deliberately broken catalog can be pushed
/// through the real loader. Constraints are left off on purpose: the point is
/// to feed the loader what a bad build could produce.
class FixtureQuranDatabase implements QuranDatabaseOpener {
  FixtureQuranDatabase({
    required this.surahs,
    this.ayahs = const <AyahDbRow>[],
  });

  final List<SurahDbRow> surahs;
  final List<AyahDbRow> ayahs;
  Future<Database>? _opening;

  @override
  Future<Database> open() => _opening ??= _create();

  Future<Database> _create() async {
    _ensureFfi();
    final Database db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.execute(
      'CREATE TABLE surahs (id INTEGER, name_ar TEXT, name_translit TEXT, '
      'ayah_count INTEGER, revelation TEXT, start_page INTEGER, '
      'basmala_mode TEXT)',
    );
    await db.execute(
      'CREATE TABLE ayahs (id INTEGER, surah INTEGER, ayah INTEGER, text TEXT)',
    );
    final Batch batch = db.batch();
    for (final SurahDbRow s in surahs) {
      batch.insert('surahs', <String, Object?>{
        'id': s.id,
        'name_ar': s.nameAr,
        'name_translit': s.nameTranslit,
        'ayah_count': s.ayahCount,
        'revelation': s.revelation,
        'start_page': 1,
        'basmala_mode': s.basmalaMode,
      });
    }
    for (final AyahDbRow a in ayahs) {
      batch.insert('ayahs', <String, Object?>{
        'surah': a.surah,
        'ayah': a.ayah,
        'text': a.text,
      });
    }
    await batch.commit(noResult: true);
    return db;
  }
}

/// Serves whatever JSON a test hands it, so deliberately corrupted reciter and
/// timing catalogs can be pushed through the real loader.
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

/// Two reciters: `a` has surah 1, `b` has surahs 1 and 2. Nobody has 3.
const String twoReciters = '''
[{"id":"a","nameAr":"أ","nameEn":"A","audioMode":"per_ayah_files",
  "basePath":"assets/audio/a","availableSurahs":[1]},
 {"id":"b","nameAr":"ب","nameEn":"B","audioMode":"per_ayah_files",
  "basePath":"assets/audio/b","availableSurahs":[1,2]}]
''';

const List<SurahDbRow> threeSurahs = <SurahDbRow>[
  SurahDbRow(id: 1, ayahCount: 3, basmalaMode: 'first_ayah'),
  SurahDbRow(id: 2, ayahCount: 3),
  SurahDbRow(id: 3, ayahCount: 3),
];

QuranRepository fixtureRepository({String reciters = twoReciters}) =>
    QuranRepositoryImpl(
      QuranLocalDataSourceImpl(
        FakeAssetReader(<String, String>{AssetPaths.recitersCatalog: reciters}),
        FixtureQuranDatabase(
          surahs: threeSurahs,
          ayahs: <AyahDbRow>[
            for (final SurahDbRow s in threeSurahs)
              for (int a = 1; a <= s.ayahCount; a++) AyahDbRow(s.id, a, 'ب'),
          ],
        ),
      ),
    );
