import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mirqat/core/error/failures.dart';
import 'package:mirqat/data/models/reciter.dart';
import 'package:mirqat/data/repositories/quran_repository.dart';
import 'package:mirqat/services/audio/manifest_service.dart';
import 'package:mirqat/services/audio/reciter_catalog.dart';

import '../quran_db_fixtures.dart';

/// A manifest reciter. The fixture surahs all have three ayahs, so `ayahs: 3`
/// agrees with the text and anything else does not.
String manifestReciter(
  String id, {
  Map<int, int> surahs = const <int, int>{1: 3},
}) =>
    '''
{"id":"$id","nameAr":"ق $id","nameEn":"Q $id","riwayah":"hafs","bitrate":64,
 "version":"1","audioPath":"audio/{id}/{bitrate}/{s3}{a3}.mp3",
 "packPath":"packs/{id}/{bitrate}/{s3}.zip","totalBytes":10,
 "surahs":[${surahs.entries.map((MapEntry<int, int> e) => '{"n":${e.key},"ayahs":${e.value},"bytes":10,"sha256":"ab"}').join(',')}]}
''';

String manifestWith(List<String> reciters) =>
    '''
{"schemaVersion":1,"baseUrl":"https://example.invalid/cdn/","mirrors":[],
 "reciters":[${reciters.join(',')}]}
''';

void main() {
  Future<List<Reciter>> load(ReciterCatalog catalog) async {
    addTearDown(catalog.dispose);
    return (await catalog.reciters()).getOrElse(
      () => throw StateError('the catalog failed to load'),
    );
  }

  Future<List<Reciter>> mergedWith(String manifest) =>
      load(fixtureCatalog(manifest: manifest));

  test(
    'an empty manifest leaves the bundled catalog exactly as it is',
    () async {
      final List<Reciter> reciters = await mergedWith(emptyManifest);

      expect(reciters.map((Reciter r) => r.id), <String>['a', 'b']);
      expect(reciters.every((Reciter r) => r.remote == null), isTrue);
      expect(reciters.every((Reciter r) => r.remoteSurahs.isEmpty), isTrue);
    },
  );

  test(
    'a manifest entry matching a bundled id extends that reciter in place',
    () async {
      final List<Reciter> reciters = await mergedWith(
        manifestWith(<String>[
          manifestReciter('a', surahs: <int, int>{1: 3, 2: 3, 3: 3}),
        ]),
      );

      expect(reciters.map((Reciter r) => r.id), <String>['a', 'b']);
      final Reciter a = reciters.first;
      // Surah 1 ships in the app and stays a bundled surah; 2 and 3 arrive from
      // the manifest, and the bundled list is untouched.
      expect(a.availableSurahs, <int>[1]);
      expect(a.isBundledSurah(1), isTrue);
      expect(a.isBundledSurah(2), isFalse);
      expect(a.hasSurah(2), isTrue);
      expect(a.hasSurah(3), isTrue);
      expect(a.remote?.id, 'a');
    },
  );

  test(
    'a reciter only the manifest knows is appended after the bundled ones',
    () async {
      final List<Reciter> reciters = await mergedWith(
        manifestWith(<String>[manifestReciter('cdn')]),
      );

      expect(reciters.map((Reciter r) => r.id), <String>['a', 'b', 'cdn']);
      final Reciter cdn = reciters.last;
      expect(cdn.bundled, isFalse);
      expect(cdn.availableSurahs, isEmpty);
      expect(cdn.hasSurah(1), isTrue);
      expect(cdn.isBundledSurah(1), isFalse);
      expect(cdn.nameAr, 'ق cdn');
    },
  );

  test('a manifest surah whose ayah count disagrees with quran.db is dropped, '
      'not played against the wrong text', () async {
    final List<Reciter> reciters = await mergedWith(
      manifestWith(<String>[
        manifestReciter('cdn', surahs: <int, int>{1: 3, 2: 4}),
      ]),
    );

    final Reciter cdn = reciters.last;
    expect(cdn.hasSurah(1), isTrue);
    expect(cdn.hasSurah(2), isFalse);
    expect(cdn.remoteSurahs, <int>{1});
  });

  test('a manifest surah the text catalog does not have is dropped', () async {
    final List<Reciter> reciters = await mergedWith(
      manifestWith(<String>[
        manifestReciter('cdn', surahs: <int, int>{1: 3, 99: 3}),
      ]),
    );

    expect(reciters.last.remoteSurahs, <int>{1});
  });

  test(
    'a manifest reciter with nothing playable is not offered at all',
    () async {
      final List<Reciter> reciters = await mergedWith(
        manifestWith(<String>[
          manifestReciter('cdn', surahs: <int, int>{1: 7}),
        ]),
      );

      expect(reciters.map((Reciter r) => r.id), <String>['a', 'b']);
    },
  );

  test('a bundled reciter stays offered even when the manifest gives it '
      'nothing playable', () async {
    final List<Reciter> reciters = await mergedWith(
      manifestWith(<String>[
        manifestReciter('a', surahs: <int, int>{2: 4}),
      ]),
    );

    expect(reciters.map((Reciter r) => r.id), <String>['a', 'b']);
    expect(reciters.first.hasSurah(1), isTrue);
    expect(reciters.first.hasSurah(2), isFalse);
  });

  test(
    'a duplicated manifest id is taken once, from the first entry',
    () async {
      final List<Reciter> reciters = await mergedWith(
        manifestWith(<String>[
          manifestReciter('cdn', surahs: <int, int>{1: 3}),
          manifestReciter('cdn', surahs: <int, int>{1: 3, 2: 3}),
        ]),
      );

      expect(reciters.map((Reciter r) => r.id), <String>['a', 'b', 'cdn']);
      expect(reciters.last.remoteSurahs, <int>{1});
    },
  );

  test(
    'a manifest that arrives later adds its reciters without a restart',
    () async {
      // The first fetch is the background refresh `load` starts, and it fails:
      // the catalog must begin at the bundled list and pick the manifest up when
      // one finally arrives.
      int fetches = 0;
      final ManifestService manifest = fixtureManifestService(
        bundled: emptyManifest,
        client: MockClient(
          (http.Request _) async => fetches++ == 0
              ? http.Response('', 404)
              : http.Response.bytes(
                  utf8.encode(manifestWith(<String>[manifestReciter('cdn')])),
                  200,
                ),
        ),
      );
      addTearDown(manifest.dispose);
      final ReciterCatalog catalog = ReciterCatalog(
        quranRepository: fixtureRepository(),
        manifestService: manifest,
      );
      addTearDown(catalog.dispose);

      expect(
        (await catalog.reciters())
            .getOrElse(() => <Reciter>[])
            .map((Reciter r) => r.id),
        <String>['a', 'b'],
      );

      await manifest.refresh();
      await pumpEventQueue();

      expect(
        (await catalog.reciters())
            .getOrElse(() => <Reciter>[])
            .map((Reciter r) => r.id),
        <String>['a', 'b', 'cdn'],
      );
    },
  );

  test('a manifest reciter carries their portrait url, resolved against the '
      'baseUrl', () async {
    final List<Reciter> reciters = await mergedWith(
      manifestWith(<String>[
        '''
{"id":"mishary","nameAr":"مشاري","nameEn":"Mishary","riwayah":"hafs",
 "bitrate":64,"version":"1","audioPath":"audio/{id}/{bitrate}/{s3}{a3}.mp3",
 "packPath":"packs/{id}/{bitrate}/{s3}.zip","imagePath":"images/mishary.jpg",
 "surahs":[{"n":1,"ayahs":3,"bytes":10,"sha256":"ab"}]}
''',
      ]),
    );

    // This is what lets a reciter be added without an app release: they are
    // not in `reciters.json`, so the portrait can only come from here.
    final Reciter mishary = reciters.last;
    expect(mishary.id, 'mishary');
    expect(mishary.imagePath, isNull, reason: 'nothing is bundled for them');
    expect(mishary.imageUrl, 'https://example.invalid/cdn/images/mishary.jpg');
  });

  test('a manifest reciter is told which surah\'s first ayah is the basmala, '
      'read off the catalog, so a surah with no basmala file still opens '
      'with one', () async {
    final List<Reciter> reciters = await mergedWith(
      manifestWith(<String>[
        '''
{"id":"links","nameAr":"ر","nameEn":"L","riwayah":"hafs",
 "bitrate":128,"version":"1","audioPath":"https://host.invalid/l/{s3}{a3}.mp3",
 "surahs":[{"n":1,"ayahs":3},{"n":2,"ayahs":3,"hasBasmala":false}]}
''',
      ]),
    );

    // Surah 1 of the fixture catalog is `first_ayah`.
    final Reciter links = reciters.last;
    expect(links.id, 'links');
    expect(links.basmalaAyahSurah, 1);
    expect(links.borrowsBasmala, isTrue);
    expect(links.hasBasmala(2), isTrue);
  });

  test('a manifest with no portrait leaves the bundled one standing', () async {
    final List<Reciter> reciters = await mergedWith(
      manifestWith(<String>[manifestReciter('a')]),
    );

    final Reciter bundled = reciters.firstWhere((Reciter r) => r.id == 'a');
    expect(bundled.imageUrl, isNull);
  });

  test('a bundled catalog that cannot be read is a Left — a broken build is '
      'not a short list', () async {
    final QuranRepository broken = fixtureRepository(reciters: '[{');
    final ReciterCatalog catalog = fixtureCatalog(repository: broken);
    addTearDown(catalog.dispose);

    final result = await catalog.reciters();

    expect(result.isLeft(), isTrue);
    result.fold(
      (Failure f) => expect(f, isA<AssetParseFailure>()),
      (_) => fail('expected a Left'),
    );
  });

  test('a manifest that cannot be read at all is a shorter list, not a '
      'failure', () async {
    final ReciterCatalog catalog = fixtureCatalog(manifest: '{ not json');
    addTearDown(catalog.dispose);

    expect(
      (await catalog.reciters())
          .getOrElse(() => <Reciter>[])
          .map((Reciter r) => r.id),
      <String>['a', 'b'],
    );
  });
}
