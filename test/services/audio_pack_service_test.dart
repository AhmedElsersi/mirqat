import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mirqat/core/error/failures.dart';
import 'package:mirqat/data/datasources/downloads_local_data_source.dart';
import 'package:mirqat/data/models/audio_manifest.dart';
import 'package:mirqat/data/models/audio_pack.dart';
import 'package:mirqat/data/models/reciter.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:mirqat/data/repositories/downloads_repository.dart';
import 'package:mirqat/services/audio/audio_pack_service.dart';
import 'package:mirqat/services/audio/audio_resolver.dart';
import 'package:mirqat/services/audio/audio_storage.dart';
import 'package:mirqat/services/audio/pack_fetcher.dart';
import 'package:path/path.dart' as p;

import '../quran_db_fixtures.dart';

/// Surah 2 of the fixture catalog: three ayahs, basmala before ayah 1.
const Surah surah2 = Surah(
  number: 2,
  nameAr: 'س',
  nameEn: 'Two',
  ayahCount: 3,
  revelationPlace: RevelationPlace.madinah,
  bismillahMode: BismillahMode.separatePreamble,
);

/// A bundled reciter with no manifest entry at all.
const Reciter bundledOnly = Reciter(
  id: 'a',
  nameAr: 'أ',
  nameEn: 'A',
  audioMode: AudioMode.perAyahFiles,
  basePath: 'assets/audio/a',
  bundled: true,
  availableSurahs: <int>[1],
  hasIstiadhah: true,
  hasBismillah: true,
);

/// The bytes of one "recording". Content does not matter; length and digest
/// do.
List<int> clip(String name) => utf8.encode('mp3:$name');

/// A pack zip holding [names] at the top level.
List<int> packZip(List<String> names) {
  final Archive archive = Archive();
  for (final String name in names) {
    final List<int> bytes = clip(name);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }
  return ZipEncoder().encode(archive);
}

/// A manifest whose reciter `cdn` offers surah 2 at [sha] — the digest of
/// whatever zip the test is about to serve.
String manifestWith({
  required String sha,
  int bytes = 0,
  int ayahs = 3,
  bool? hasBasmala,
}) =>
    '''
{"schemaVersion":1,"baseUrl":"https://example.invalid/cdn/","mirrors":[],
 "reciters":[{"id":"cdn","nameAr":"ق","nameEn":"Q","riwayah":"hafs",
   "bitrate":128,"version":"3","audioPath":"audio/{id}/{bitrate}/{s3}{a3}.mp3",
   "packPath":"packs/{id}/{bitrate}/{s3}.zip","totalBytes":$bytes,
   "surahs":[{"n":2,"ayahs":$ayahs,"bytes":$bytes,"sha256":"$sha"${hasBasmala == null ? '' : ',"hasBasmala":$hasBasmala'}}]}]}
''';

/// Writes whatever bytes it was built with, and records what it was asked for.
class FakePackFetcher implements PackFetcher {
  FakePackFetcher(this.bytes);

  final List<int> bytes;
  final List<Uri> fetched = <Uri>[];
  final List<String> cancelled = <String>[];
  Object? failWith;

  @override
  Future<File> fetch({
    required Uri url,
    required File destination,
    required String taskId,
    bool requiresWiFi = false,
    void Function(double progress)? onProgress,
  }) async {
    fetched.add(url);
    final Object? failure = failWith;
    if (failure != null) throw failure;

    onProgress?.call(-1);
    onProgress?.call(0.5);
    destination.parent.createSync(recursive: true);
    destination.writeAsBytesSync(bytes, flush: true);
    onProgress?.call(1);
    return destination;
  }

  @override
  Future<void> cancel(String taskId) async => cancelled.add(taskId);
}

void main() {
  late Directory stateDir;
  late Directory storageRoot;

  setUp(() {
    stateDir = Directory.systemTemp.createTempSync('mirqat_packs_state');
    storageRoot = Directory.systemTemp.createTempSync('mirqat_packs');
  });

  tearDown(() async {
    for (final Directory dir in <Directory>[stateDir, storageRoot]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  Future<DownloadsRepository> openDownloads() =>
      fixtureDownloadsRepository(stateDir);

  AudioStorage storage() =>
      AudioStorage(resolveStorageDirectory: () async => storageRoot);

  /// The service, the reciter it will be asked about, and the fetcher standing
  /// in for the CDN.
  Future<
    ({
      AudioPackService service,
      Reciter reciter,
      FakePackFetcher fetcher,
      AudioStorage storage,
    })
  >
  serviceFor({
    List<String> entries = const <String>[
      '002000.mp3',
      '002001.mp3',
      '002002.mp3',
      '002003.mp3',
    ],
    String? sha,
    int declaredAyahs = 3,
    bool? hasBasmala,
  }) async {
    final List<int> zip = packZip(entries);
    final String digest = sha ?? sha256.convert(zip).toString();
    final String manifestJson = manifestWith(
      sha: digest,
      // The manifest describes the very bytes the fetcher will serve; the
      // length check compares against this before the digest.
      bytes: zip.length,
      ayahs: declaredAyahs,
      hasBasmala: hasBasmala,
    );

    final FakePackFetcher fetcher = FakePackFetcher(zip);
    final AudioStorage audioStorage = storage();
    final AudioPackService service = AudioPackService(
      manifestService: fixtureManifestService(bundled: manifestJson),
      audioStorage: audioStorage,
      downloadsRepository: await openDownloads(),
      packFetcher: () => fetcher,
    );
    addTearDown(service.dispose);

    final ManifestReciter entry = AudioManifest.fromJson(
      jsonDecode(manifestJson),
      'test',
    ).reciters.single;

    return (
      service: service,
      reciter: Reciter.remoteOnly(entry),
      fetcher: fetcher,
      storage: audioStorage,
    );
  }

  File installedFile(int surah, int ayah, {int bitrate = 128}) => File(
    p.join(
      storageRoot.path,
      'audio',
      'cdn',
      '$bitrate',
      '${surah.toString().padLeft(3, '0')}${ayah.toString().padLeft(3, '0')}.mp3',
    ),
  );

  test('a pack is fetched from the manifest url, verified, unzipped into the '
      'layout the resolver reads, and recorded', () async {
    final harness = await serviceFor();

    final Either<Failure, InstalledPack> result = await harness.service
        .download(reciter: harness.reciter, surahNumber: 2);

    expect(result.isRight(), isTrue, reason: '$result');
    expect(
      harness.fetcher.fetched.single.toString(),
      'https://example.invalid/cdn/packs/cdn/128/002.zip',
    );
    for (int ayah = 0; ayah <= 3; ayah++) {
      expect(
        installedFile(2, ayah).existsSync(),
        isTrue,
        reason: 'ayah $ayah should be on disk',
      );
    }

    final InstalledPack pack = result.getOrElse(
      () => throw StateError('no pack'),
    );
    expect(pack.reciterId, 'cdn');
    expect(pack.surahNumber, 2);
    expect(pack.bitrate, 128);
    expect(pack.version, '3');
    expect(pack.ayahs, 3);

    final Either<Failure, List<InstalledPack>> installed = await harness.service
        .installed();
    expect(installed.getOrElse(() => <InstalledPack>[]).single.key, 'cdn:002');
  });

  test('the zip is not kept once it is unpacked', () async {
    final harness = await serviceFor();
    await harness.service.download(reciter: harness.reciter, surahNumber: 2);

    final Directory packs = Directory(
      p.join(storageRoot.path, 'audio', '.packs'),
    );
    expect(
      packs.existsSync() ? packs.listSync() : <FileSystemEntity>[],
      isEmpty,
    );
  });

  test(
    'an installed pack is what the resolver plays, without a network call',
    () async {
      final harness = await serviceFor();
      await harness.service.download(reciter: harness.reciter, surahNumber: 2);

      final AudioResolver resolver = AudioResolver(
        quranRepository: fixtureRepository(),
        manifestService: fixtureManifestService(
          bundled: manifestWith(sha: 'unused'),
        ),
        audioStorage: harness.storage,
      );
      final SurahAudio audio = await resolver.forSurah(
        reciter: harness.reciter,
        surah: surah2,
      );

      expect(audio.isLocal(2), isTrue);
      expect(
        (audio.sourceFor(2) as UriAudioSource).uri.toString(),
        startsWith('file://'),
      );
      expect(
        (audio.basmala()! as UriAudioSource).uri.toString(),
        endsWith('002000.mp3'),
      );
    },
  );

  test('a pack whose bytes do not match the manifest digest is refused and '
      'leaves nothing behind', () async {
    final harness = await serviceFor(sha: 'a' * 64);

    final Either<Failure, InstalledPack> result = await harness.service
        .download(reciter: harness.reciter, surahNumber: 2);

    expect(result.isLeft(), isTrue);
    result.fold(
      (Failure f) => expect(f, isA<DownloadFailure>()),
      (_) => fail('expected a Left'),
    );
    expect(installedFile(2, 1).existsSync(), isFalse);
    expect(
      (await harness.service.installed()).getOrElse(() => <InstalledPack>[]),
      isEmpty,
    );
    expect(
      harness.service.stateFor(reciterId: 'cdn', surahNumber: 2).status,
      PackStatus.failed,
    );
  });

  test('a pack holding fewer files than the catalog predicts is installed '
      'anyway — the digest is the check, the count is a warning', () async {
    final harness = await serviceFor(
      entries: <String>['002001.mp3', '002003.mp3'],
    );

    final Either<Failure, InstalledPack> result = await harness.service
        .download(reciter: harness.reciter, surahNumber: 2);

    expect(result.isRight(), isTrue, reason: '$result');
    expect(installedFile(2, 1).existsSync(), isTrue);
    expect(installedFile(2, 3).existsSync(), isTrue);
    // What is missing simply streams; nothing pretends ayah 2 is here.
    expect(installedFile(2, 2).existsSync(), isFalse);
    expect(
      result.getOrElse(() => throw StateError('no pack')).ayahs,
      2,
      reason: 'the record counts the ayahs that actually landed',
    );
  });

  test('a pack with no ayah files at all is refused', () async {
    final harness = await serviceFor(entries: <String>['readme.txt']);

    final Either<Failure, InstalledPack> result = await harness.service
        .download(reciter: harness.reciter, surahNumber: 2);

    expect(result.isLeft(), isTrue);
    expect(installedFile(2, 1).existsSync(), isFalse);
  });

  test('a pack that declares a basmala but ships none still installs its '
      'ayahs', () async {
    final harness = await serviceFor(
      entries: <String>['002001.mp3', '002002.mp3', '002003.mp3'],
      hasBasmala: true,
    );

    final Either<Failure, InstalledPack> result = await harness.service
        .download(reciter: harness.reciter, surahNumber: 2);

    expect(result.isRight(), isTrue, reason: '$result');
    expect(installedFile(2, 0).existsSync(), isFalse);
    expect(installedFile(2, 1).existsSync(), isTrue);
  });

  test(
    'a pack for a surah that declares no basmala installs without one',
    () async {
      final harness = await serviceFor(
        entries: <String>['002001.mp3', '002002.mp3', '002003.mp3'],
        hasBasmala: false,
      );

      final Either<Failure, InstalledPack> result = await harness.service
          .download(reciter: harness.reciter, surahNumber: 2);

      expect(result.isRight(), isTrue, reason: '$result');
      expect(installedFile(2, 0).existsSync(), isFalse);
      expect(installedFile(2, 1).existsSync(), isTrue);
    },
  );

  test('a zip entry that tries to escape its directory is ignored', () async {
    final harness = await serviceFor(
      entries: <String>[
        '../../escaped.mp3',
        '../../002009.mp3',
        'nested/002001.mp3',
        '002002.mp3',
        '002003.mp3',
      ],
    );

    final Either<Failure, InstalledPack> result = await harness.service
        .download(reciter: harness.reciter, surahNumber: 2);

    // The nested entry is taken by its base name, the escaping ones are not
    // taken at all, and nothing is written outside the reciter's directory.
    expect(result.isRight(), isTrue, reason: '$result');
    expect(installedFile(2, 1).existsSync(), isTrue);
    expect(File(p.join(storageRoot.path, 'escaped.mp3')).existsSync(), isFalse);
    expect(installedFile(2, 9).existsSync(), isTrue);
    expect(
      Directory(p.join(storageRoot.path, 'audio', 'cdn', '128'))
          .listSync()
          .whereType<File>()
          .map((File f) => p.basename(f.path))
          .toSet(),
      <String>{'002001.mp3', '002002.mp3', '002003.mp3', '002009.mp3'},
    );
  });

  test('a manifest surah with no digest is installed anyway, because the app '
      'does not control that field', () async {
    final harness = await serviceFor(sha: '');

    expect(
      (await harness.service.download(
        reciter: harness.reciter,
        surahNumber: 2,
      )).isRight(),
      isTrue,
    );
    expect(installedFile(2, 1).existsSync(), isTrue);
  });

  test('a bundled reciter has no pack to download, and is told so', () async {
    final harness = await serviceFor();

    final Either<Failure, InstalledPack> result = await harness.service
        .download(reciter: bundledOnly, surahNumber: 1);

    expect(result.isLeft(), isTrue);
    expect(harness.fetcher.fetched, isEmpty);
  });

  test('a failed fetch is reported, not swallowed', () async {
    final harness = await serviceFor();
    harness.fetcher.failWith = const SocketException('offline');

    final Either<Failure, InstalledPack> result = await harness.service
        .download(reciter: harness.reciter, surahNumber: 2);

    expect(result.isLeft(), isTrue);
    expect(
      harness.service.stateFor(reciterId: 'cdn', surahNumber: 2).status,
      PackStatus.failed,
    );
  });

  test('the download announces each step it is on', () async {
    final harness = await serviceFor();
    final List<PackStatus> seen = <PackStatus>[];
    harness.service.changes.listen((PackDownload d) => seen.add(d.status));

    await harness.service.download(reciter: harness.reciter, surahNumber: 2);
    await pumpEventQueue();

    expect(
      seen,
      containsAllInOrder(<PackStatus>[
        PackStatus.queued,
        PackStatus.downloading,
        PackStatus.verifying,
        PackStatus.installing,
        PackStatus.installed,
      ]),
    );
  });

  test('deleting a pack frees its files and forgets it, and leaves another '
      'surah alone', () async {
    final harness = await serviceFor();
    await harness.service.download(reciter: harness.reciter, surahNumber: 2);
    // A file from a surah nobody asked to delete, in the same directory.
    installedFile(3, 1)
      ..createSync(recursive: true)
      ..writeAsStringSync('other surah');

    final Either<Failure, Unit> result = await harness.service.delete(
      reciterId: 'cdn',
      surahNumber: 2,
      bitrate: 128,
    );

    expect(result.isRight(), isTrue);
    expect(installedFile(2, 1).existsSync(), isFalse);
    expect(installedFile(2, 0).existsSync(), isFalse);
    expect(installedFile(3, 1).existsSync(), isTrue);
    expect(
      (await harness.service.installed()).getOrElse(() => <InstalledPack>[]),
      isEmpty,
    );
  });

  test(
    'a truncated pack is refused on its length, before it is even hashed',
    () async {
      // The manifest declares a size the fetcher will not deliver: the length
      // check is what catches an interrupted download without reading 40 MB.
      final List<int> zip = packZip(<String>['002001.mp3']);
      final FakePackFetcher fetcher = FakePackFetcher(zip);
      final AudioPackService service = AudioPackService(
        manifestService: fixtureManifestService(
          bundled: manifestWith(
            sha: sha256.convert(zip).toString(),
            bytes: zip.length + 1024,
          ),
        ),
        audioStorage: storage(),
        downloadsRepository: await openDownloads(),
        packFetcher: () => fetcher,
      );
      addTearDown(service.dispose);
      final ManifestReciter entry = AudioManifest.fromJson(
        jsonDecode(manifestWith(sha: 'x', bytes: 1)),
        'test',
      ).reciters.single;

      final Either<Failure, InstalledPack> result = await service.download(
        reciter: Reciter.remoteOnly(entry),
        surahNumber: 2,
      );

      expect(result.isLeft(), isTrue);
      result.fold(
        (Failure f) => expect(f.message, contains('bytes')),
        (_) => fail('expected a Left'),
      );
      expect(installedFile(2, 1).existsSync(), isFalse);
    },
  );

  test('a failed download is remembered so it can be retried, and is not '
      'listed as saved', () async {
    final harness = await serviceFor();
    harness.fetcher.failWith = const SocketException('offline');

    await harness.service.download(reciter: harness.reciter, surahNumber: 2);

    expect(
      (await harness.service.installed()).getOrElse(() => <InstalledPack>[]),
      isEmpty,
      reason: 'a failure has no files and no size to free',
    );
    final List<InstalledPack> failed = (await harness.service.failed())
        .getOrElse(() => <InstalledPack>[]);
    expect(failed.single.surahNumber, 2);
    expect(failed.single.state, PackState.failed);

    // And the retry goes through once the network is back.
    harness.fetcher.failWith = null;
    final Either<Failure, int> retried = await harness.service.retryFailed(
      reciters: <Reciter>[harness.reciter],
    );

    expect(retried.getOrElse(() => 0), 1);
    expect(installedFile(2, 1).existsSync(), isTrue);
    expect(
      (await harness.service.failed()).getOrElse(() => <InstalledPack>[]),
      isEmpty,
    );
  });

  test('a reciter whose manifest version has moved on has its surahs marked '
      'stale, and they still play', () async {
    final harness = await serviceFor();
    await harness.service.download(reciter: harness.reciter, surahNumber: 2);

    // The same storage and the same rows, now read against a manifest whose
    // reciter is at version 4.
    final AudioPackService newer = AudioPackService(
      manifestService: fixtureManifestService(
        bundled: manifestWith(
          sha: 'x',
          bytes: 1,
        ).replaceAll('"version":"3"', '"version":"4"'),
      ),
      audioStorage: harness.storage,
      downloadsRepository: await openDownloads(),
      packFetcher: () => harness.fetcher,
    );
    addTearDown(newer.dispose);

    expect((await newer.reconcile()).getOrElse(() => 0), 1);

    final InstalledPack pack = (await newer.installed())
        .getOrElse(() => <InstalledPack>[])
        .single;
    expect(pack.isStale, isTrue);
    // Stale is not gone: a superseded take beats silence, and the files are
    // still where the resolver looks.
    expect(installedFile(2, 1).existsSync(), isTrue);
  });

  test(
    'deleting a whole reciter frees every bitrate it has on the device',
    () async {
      final harness = await serviceFor();
      await harness.service.download(reciter: harness.reciter, surahNumber: 2);
      // A second quality of the same reciter, as a later setting change would
      // leave behind.
      installedFile(2, 1, bitrate: 32)
        ..createSync(recursive: true)
        ..writeAsStringSync('another bitrate');

      final Either<Failure, Unit> result = await harness.service.deleteReciter(
        'cdn',
      );

      expect(result.isRight(), isTrue);
      expect(installedFile(2, 1).existsSync(), isFalse);
      expect(installedFile(2, 1, bitrate: 32).existsSync(), isFalse);
      expect(
        (await harness.service.installed()).getOrElse(() => <InstalledPack>[]),
        isEmpty,
      );
    },
  );

  test(
    'an install is remembered across a restart of the data source',
    () async {
      final harness = await serviceFor();
      await harness.service.download(reciter: harness.reciter, surahNumber: 2);

      final DownloadsLocalDataSource reopened = await openFixtureDownloads(
        stateDir,
      );

      final InstalledPack? pack = await reopened.get('cdn', 2);
      expect(pack, isNotNull);
      expect(pack!.version, '3');
      expect(pack.bytes, greaterThan(0));
      expect(pack.state, PackState.complete);
    },
  );
}
