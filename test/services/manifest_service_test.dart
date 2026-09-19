import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mirqat/data/models/audio_manifest.dart';
import 'package:mirqat/services/audio/manifest_service.dart';
import 'package:path/path.dart' as p;

import '../quran_db_fixtures.dart';

/// One reciter, [id], offering surah 1.
String manifestJson({
  String id = 'cdn',
  String baseUrl = 'https://example.invalid/cdn/',
  int schemaVersion = 1,
}) =>
    '''
{"schemaVersion":$schemaVersion,"baseUrl":"$baseUrl","mirrors":[],
 "reciters":[{"id":"$id","nameAr":"ق","nameEn":"Q","riwayah":"hafs",
   "bitrate":64,"version":"1","audioPath":"audio/{id}/{bitrate}/{s3}{a3}.mp3",
   "packPath":"packs/{id}/{bitrate}/{s3}.zip","totalBytes":10,
   "surahs":[{"n":1,"ayahs":3,"bytes":10,"sha256":"ab"}]}]}
''';

void main() {
  Directory tempCache() {
    final Directory dir = Directory.systemTemp.createTempSync('mirqat_cache');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    return dir;
  }

  /// [http.Response] encodes a `String` body as latin1, which a manifest's
  /// Arabic names are not: they go over the wire as utf8 bytes, the way the
  /// CDN serves them.
  MockClient serving(String body, {int status = 200}) => MockClient(
    (http.Request _) async => http.Response.bytes(
      utf8.encode(body),
      status,
      headers: <String, String>{
        'content-type': 'application/json; charset=utf-8',
      },
    ),
  );

  test('falls back to the bundled manifest when there is no cache and the '
      'network is unreachable', () async {
    final ManifestService service = fixtureManifestService(
      bundled: manifestJson(id: 'bundled_copy'),
      client: MockClient(
        (http.Request _) async => throw const SocketException('offline'),
      ),
    );
    addTearDown(service.dispose);

    final AudioManifest loaded = await service.load();

    expect(loaded.reciters.single.id, 'bundled_copy');
    expect(service.current, loaded);
  });

  test('a manifest that is not the supported schema leaves an empty '
      'manifest rather than a half-read one', () async {
    final ManifestService service = fixtureManifestService(
      bundled: manifestJson(schemaVersion: 99),
    );
    addTearDown(service.dispose);

    expect(await service.load(), AudioManifest.empty);
  });

  test(
    'a fetched manifest replaces the bundled one and is announced',
    () async {
      final ManifestService service = fixtureManifestService(
        bundled: emptyManifest,
        client: serving(manifestJson(id: 'fetched')),
        cacheDirectory: () async => tempCache(),
      );
      addTearDown(service.dispose);

      final List<AudioManifest> announced = <AudioManifest>[];
      service.changes.listen(announced.add);

      expect((await service.load()).reciters, isEmpty);
      final AudioManifest refreshed = await service.refresh();

      expect(refreshed.reciters.single.id, 'fetched');
      expect(service.current, refreshed);
      await pumpEventQueue();
      expect(announced.last.reciters.single.id, 'fetched');
    },
  );

  test('a fetched manifest is cached, and the cache is preferred over the '
      'bundled copy on the next start', () async {
    final Directory cache = tempCache();
    final ManifestService first = fixtureManifestService(
      client: serving(manifestJson(id: 'from_cdn')),
      cacheDirectory: () async => cache,
    );
    addTearDown(first.dispose);
    await first.refresh();

    expect(File(p.join(cache.path, 'manifest.json')).existsSync(), isTrue);

    final ManifestService second = fixtureManifestService(
      bundled: manifestJson(id: 'bundled_copy'),
      cacheDirectory: () async => cache,
    );
    addTearDown(second.dispose);

    expect((await second.load()).reciters.single.id, 'from_cdn');
  });

  test('a manifest fetched with nowhere to cache it is still used', () async {
    final ManifestService service = fixtureManifestService(
      client: serving(manifestJson(id: 'fetched')),
    );
    addTearDown(service.dispose);

    expect((await service.refresh()).reciters.single.id, 'fetched');
  });

  test(
    'a failed or malformed fetch keeps the manifest already in use',
    () async {
      for (final MockClient client in <MockClient>[
        serving('', status: 500),
        serving('not json'),
        serving('{"schemaVersion":1}'),
      ]) {
        final ManifestService service = fixtureManifestService(
          bundled: manifestJson(id: 'bundled_copy'),
          client: client,
        );
        addTearDown(service.dispose);

        final AudioManifest local = await service.load();
        expect(await service.refresh(), local);
        expect(service.current.reciters.single.id, 'bundled_copy');
      }
    },
  );

  test(
    'a corrupt cache is ignored in favour of the bundled manifest',
    () async {
      final Directory cache = tempCache();
      File(p.join(cache.path, 'manifest.json')).writeAsStringSync('{ not json');

      final ManifestService service = fixtureManifestService(
        bundled: manifestJson(id: 'bundled_copy'),
        cacheDirectory: () async => cache,
      );
      addTearDown(service.dispose);

      expect((await service.load()).reciters.single.id, 'bundled_copy');
    },
  );

  test('load reads once, however many callers ask', () async {
    int reads = 0;
    final ManifestService service = fixtureManifestService(
      client: MockClient((http.Request _) async {
        reads++;
        return http.Response.bytes(utf8.encode(manifestJson()), 200);
      }),
    );
    addTearDown(service.dispose);

    await Future.wait<AudioManifest>(<Future<AudioManifest>>[
      service.load(),
      service.load(),
      service.load(),
    ]);
    await pumpEventQueue();

    expect(reads, 1);
  });

  test('an ayah url is the template with surah and ayah padded to three, '
      'and the basmala is ayah 000', () {
    final ManifestReciter reciter = AudioManifest.fromJson(<String, dynamic>{
      'schemaVersion': 1,
      'baseUrl': 'https://example.invalid/cdn/',
      'reciters': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'cdn',
          'nameAr': 'ق',
          'nameEn': 'Q',
          'bitrate': 64,
          'audioPath': 'audio/{id}/{bitrate}/{s3}{a3}.mp3',
          'packPath': 'packs/{id}/{bitrate}/{s3}.zip',
          'surahs': <Map<String, dynamic>>[],
        },
      ],
    }, 'test').reciters.single;

    expect(reciter.audioPathFor(2, 1), 'audio/cdn/64/002001.mp3');
    expect(reciter.audioPathFor(2, 0), 'audio/cdn/64/002000.mp3');
    expect(reciter.packPathFor(114), 'packs/cdn/64/114.zip');
  });

  test('a baseUrl with no trailing slash keeps its last segment', () {
    // The published manifest's baseUrl is a bucket root with no trailing
    // slash; `Uri.resolve` would treat a last segment as a file name and drop
    // it, which would silently point every ayah at the wrong host path.
    AudioManifest manifestWithBase(String baseUrl) =>
        AudioManifest.fromJson(<String, dynamic>{
          'schemaVersion': 1,
          'baseUrl': baseUrl,
          'reciters': <Map<String, dynamic>>[],
        }, 'test');

    expect(
      manifestWithBase(
        'https://pub-f2046e05789e4bd5889880fb0c6d3168.r2.dev',
      ).urlFor('audio/cdn/64/001001.mp3').toString(),
      'https://pub-f2046e05789e4bd5889880fb0c6d3168.r2.dev/audio/cdn/64/001001.mp3',
    );
    expect(
      manifestWithBase(
        'https://example.invalid/iqra-cdn',
      ).urlFor('packs/cdn/64/001.zip').toString(),
      'https://example.invalid/iqra-cdn/packs/cdn/64/001.zip',
    );
    expect(
      manifestWithBase(
        'https://example.invalid/iqra-cdn/',
      ).urlFor('packs/cdn/64/001.zip').toString(),
      'https://example.invalid/iqra-cdn/packs/cdn/64/001.zip',
    );
  });

  test('a surah may declare whether it has a basmala, or say nothing', () {
    List<ManifestSurah> surahsFrom(String entry) => AudioManifest.fromJson(
      jsonDecode('''
{"schemaVersion":1,"baseUrl":"https://example.invalid/","reciters":[
 {"id":"cdn","nameAr":"ق","nameEn":"Q","bitrate":64,
  "audioPath":"a/{s3}{a3}.mp3","packPath":"p/{s3}.zip","surahs":[$entry]}]}
'''),
      'test',
    ).reciters.single.surahs;

    expect(
      surahsFrom('{"n":2,"ayahs":286,"hasBasmala":true}').single.hasBasmala,
      isTrue,
    );
    expect(
      surahsFrom('{"n":9,"ayahs":129,"hasBasmala":false}').single.hasBasmala,
      isFalse,
    );
    // Not declared: null, not false — the difference is whether the app may
    // assume the layout.
    expect(surahsFrom('{"n":1,"ayahs":7}').single.hasBasmala, isNull);
  });

  test('a path resolves against the manifest baseUrl', () {
    final AudioManifest manifest = AudioManifest.fromJson(<String, dynamic>{
      'schemaVersion': 1,
      'baseUrl': 'https://example.invalid/cdn/',
      'reciters': <Map<String, dynamic>>[],
    }, 'test');

    expect(
      manifest.urlFor('audio/cdn/64/001001.mp3').toString(),
      'https://example.invalid/cdn/audio/cdn/64/001001.mp3',
    );
  });
}
