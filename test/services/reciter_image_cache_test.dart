import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mirqat/data/models/reciter.dart';
import 'package:mirqat/services/audio/audio_storage.dart';
import 'package:mirqat/services/reciter_image_cache.dart';

const Reciter remote = Reciter(
  id: 'mishary',
  nameAr: 'مشاري',
  nameEn: 'Mishary',
  audioMode: AudioMode.perAyahFiles,
  basePath: '',
  bundled: false,
  availableSurahs: <int>[],
  hasIstiadhah: false,
  hasBismillah: false,
  imageUrl: 'https://pub-example.r2.dev/images/mishary.jpg',
);

const Reciter withoutPortrait = Reciter(
  id: 'nobody',
  nameAr: 'ن',
  nameEn: 'N',
  audioMode: AudioMode.perAyahFiles,
  basePath: '',
  bundled: false,
  availableSurahs: <int>[],
  hasIstiadhah: false,
  hasBismillah: false,
);

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('mirqat_portraits');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  ReciterImageCache cacheWith(MockClient client) => ReciterImageCache(
    audioStorage: AudioStorage(resolveStorageDirectory: () async => root),
    client: client,
  );

  test('a portrait is fetched once and read from disk after', () async {
    int fetches = 0;
    final ReciterImageCache cache = cacheWith(
      MockClient((http.Request _) async {
        fetches++;
        return http.Response.bytes(<int>[1, 2, 3, 4], 200);
      }),
    );

    final File? first = await cache.imageFor(remote);
    expect(first, isNotNull);
    expect(first!.path, endsWith('images/mishary.jpg'));
    expect(first.readAsBytesSync(), <int>[1, 2, 3, 4]);
    expect(fetches, 1);

    // A second cache over the same storage — a later launch — reads the file
    // rather than the network.
    final File? again = await cacheWith(
      MockClient((_) async => fail('nothing should be fetched')),
    ).imageFor(remote);
    expect(again?.path, first.path);
  });

  test('one fetch serves every row asking at once', () async {
    int fetches = 0;
    final ReciterImageCache cache = cacheWith(
      MockClient((http.Request _) async {
        fetches++;
        return http.Response.bytes(<int>[9], 200);
      }),
    );

    await Future.wait<File?>(<Future<File?>>[
      cache.imageFor(remote),
      cache.imageFor(remote),
      cache.imageFor(remote),
    ]);

    expect(fetches, 1);
  });

  test('a reciter with no portrait asks for nothing', () async {
    final ReciterImageCache cache = cacheWith(
      MockClient((_) async => fail('nothing should be fetched')),
    );

    expect(await cache.imageFor(withoutPortrait), isNull);
  });

  test(
    'a failed fetch is null, not an exception — the initial stands in',
    () async {
      for (final MockClient client in <MockClient>[
        MockClient((_) async => http.Response('nope', 404)),
        MockClient((_) async => http.Response.bytes(<int>[], 200)),
        MockClient((_) async => throw const SocketException('offline')),
      ]) {
        expect(await cacheWith(client).imageFor(remote), isNull);
      }
      // And nothing half-written was left behind to be mistaken for a portrait.
      final Directory images = Directory('${root.path}/images');
      expect(
        images.existsSync() ? images.listSync() : <FileSystemEntity>[],
        isEmpty,
      );
    },
  );

  test('a platform with nowhere to write simply has no portraits', () async {
    final ReciterImageCache cache = ReciterImageCache(
      audioStorage: AudioStorage(
        resolveStorageDirectory: () async =>
            throw UnsupportedError('no storage'),
      ),
      client: MockClient((_) async => http.Response.bytes(<int>[1], 200)),
    );

    expect(await cache.imageFor(remote), isNull);
  });
}
