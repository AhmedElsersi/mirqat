import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/error/failures.dart';
import 'package:mirqat/data/models/reciter.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:mirqat/data/repositories/quran_repository.dart';
import 'package:mirqat/services/audio/audio_availability.dart';
import 'package:mirqat/services/audio/reciter_catalog.dart';

import '../quran_db_fixtures.dart';

void main() {
  late QuranRepository repository;
  late AudioAvailability availability;

  setUp(() {
    repository = fixtureRepository();
    availability = AudioAvailability(
      reciterCatalog: ReciterCatalog(
        quranRepository: repository,
        manifestService: fixtureManifestService(),
      ),
    );
  });

  Future<List<String>> idsFor(int surahNumber) async {
    final Surah surah = (await repository.getSurah(
      surahNumber,
    )).getOrElse(() => throw StateError('no surah $surahNumber'));
    return (await availability.recitersFor(surah))
        .getOrElse(() => throw StateError('lookup failed'))
        .map((Reciter r) => r.id)
        .toList();
  }

  test('lists every reciter that has the surah, in catalog order', () async {
    expect(await idsFor(1), <String>['a', 'b']);
    expect(await idsFor(2), <String>['b']);
  });

  test('is empty for a surah nobody has recorded', () async {
    expect(await idsFor(3), isEmpty);
  });

  test('the catalog lists every surah regardless of audio', () async {
    expect(
      (await repository.getSurahs())
          .getOrElse(() => <Surah>[])
          .map((Surah s) => s.number),
      <int>[1, 2, 3],
    );
  });

  test('a manifest reciter is available for a surah nobody ships', () async {
    const String manifest = '''
{"schemaVersion":1,"baseUrl":"https://example.invalid/cdn/","mirrors":[],
 "reciters":[{"id":"cdn","nameAr":"ق","nameEn":"Q","riwayah":"hafs",
   "bitrate":64,"version":"1","audioPath":"audio/{id}/{bitrate}/{s3}{a3}.mp3",
   "packPath":"packs/{id}/{bitrate}/{s3}.zip","totalBytes":10,
   "surahs":[{"n":3,"ayahs":3,"bytes":10,"sha256":"ab"}]}]}
''';
    final ReciterCatalog catalog = ReciterCatalog(
      quranRepository: repository,
      manifestService: fixtureManifestService(bundled: manifest),
    );
    addTearDown(catalog.dispose);
    final Surah surah = (await repository.getSurah(
      3,
    )).getOrElse(() => throw StateError('no surah 3'));

    final result = await AudioAvailability(
      reciterCatalog: catalog,
    ).recitersFor(surah);

    expect(
      result.getOrElse(() => <Reciter>[]).map((Reciter r) => r.id),
      <String>['cdn'],
    );
  });

  test('a reciter catalog that fails to load is a Left, not an empty '
      'answer', () async {
    final QuranRepository broken = fixtureRepository(reciters: '[{');
    final Surah surah = (await broken.getSurah(
      1,
    )).getOrElse(() => throw StateError('no surah 1'));
    final result = await AudioAvailability(
      reciterCatalog: fixtureCatalog(repository: broken),
    ).recitersFor(surah);
    expect(result.isLeft(), isTrue);
    result.fold(
      (Failure f) => expect(f, isA<AssetParseFailure>()),
      (_) => fail('expected a Left'),
    );
  });
}
