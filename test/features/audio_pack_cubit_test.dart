import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/data/models/audio_manifest.dart';
import 'package:mirqat/data/models/audio_pack.dart';
import 'package:mirqat/data/models/reciter.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:mirqat/features/session/cubit/audio_pack_cubit.dart';
import 'package:mirqat/services/audio/audio_pack_service.dart';
import 'package:mirqat/services/audio/audio_storage.dart';
import 'package:mirqat/services/audio/pack_fetcher.dart';

import '../quran_db_fixtures.dart';

/// Surah 1 of the fixture catalog, which the bundled reciter ships.
const Surah surah1 = Surah(
  number: 1,
  nameAr: 'س',
  nameEn: 'One',
  ayahCount: 3,
  revelationPlace: RevelationPlace.makkah,
  bismillahMode: BismillahMode.countedAsAyah1,
);

const Surah surah2 = Surah(
  number: 2,
  nameAr: 'س',
  nameEn: 'Two',
  ayahCount: 3,
  revelationPlace: RevelationPlace.madinah,
  bismillahMode: BismillahMode.separatePreamble,
);

/// The bundled reciter of the fixture catalog: surah 1 ships, surah 2 does
/// not.
const Reciter bundledReciter = Reciter(
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

List<int> packZip() {
  final Archive archive = Archive();
  for (final String name in <String>[
    '002000.mp3',
    '002001.mp3',
    '002002.mp3',
    '002003.mp3',
  ]) {
    final List<int> bytes = utf8.encode('mp3:$name');
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }
  return ZipEncoder().encode(archive);
}

String manifestJson(String sha, int bytes) =>
    '''
{"schemaVersion":1,"baseUrl":"https://example.invalid/cdn/","mirrors":[],
 "reciters":[{"id":"a","nameAr":"أ","nameEn":"A","riwayah":"hafs",
   "bitrate":64,"version":"2","audioPath":"audio/{id}/{bitrate}/{s3}{a3}.mp3",
   "packPath":"packs/{id}/{bitrate}/{s3}.zip","totalBytes":$bytes,
   "surahs":[{"n":2,"ayahs":3,"bytes":$bytes,"sha256":"$sha"}]}]}
''';

class _Fetcher implements PackFetcher {
  _Fetcher(this.bytes);

  final List<int> bytes;
  Object? failWith;

  @override
  Future<File> fetch({
    required Uri url,
    required File destination,
    required String taskId,
    bool requiresWiFi = false,
    void Function(double progress)? onProgress,
  }) async {
    final Object? failure = failWith;
    if (failure != null) throw failure;
    onProgress?.call(0.25);
    destination.parent.createSync(recursive: true);
    destination.writeAsBytesSync(bytes, flush: true);
    return destination;
  }

  @override
  Future<void> cancel(String taskId) async {}
}

void main() {
  late Directory stateDir;
  late Directory storageRoot;
  late _Fetcher fetcher;
  late AudioPackService service;
  late Reciter remoteReciter;

  setUp(() async {
    stateDir = Directory.systemTemp.createTempSync('mirqat_pack_cubit_state');
    storageRoot = Directory.systemTemp.createTempSync('mirqat_pack_cubit');

    final List<int> zip = packZip();
    final String json = manifestJson(
      sha256.convert(zip).toString(),
      zip.length,
    );
    fetcher = _Fetcher(zip);

    service = AudioPackService(
      manifestService: fixtureManifestService(bundled: json),
      audioStorage: AudioStorage(
        resolveStorageDirectory: () async => storageRoot,
      ),
      downloadsRepository: await fixtureDownloadsRepository(stateDir),
      packFetcher: () => fetcher,
    );

    remoteReciter = bundledReciter.withRemote(
      AudioManifest.fromJson(jsonDecode(json), 'test').reciters.single,
    );
  });

  tearDown(() async {
    await service.dispose();
    for (final Directory dir in <Directory>[stateDir, storageRoot]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  AudioPackCubit open() {
    final AudioPackCubit cubit = AudioPackCubit(packService: service);
    addTearDown(cubit.close);
    return cubit;
  }

  test('a bundled surah offers nothing to download', () async {
    final AudioPackCubit cubit = open();

    await cubit.watch(reciter: remoteReciter, surah: surah1);

    expect(cubit.state.isBundled, isTrue);
    expect(cubit.state.isInstalled, isFalse);
  });

  test(
    'a manifest surah can be downloaded, and reads back as on the device',
    () async {
      final AudioPackCubit cubit = open();
      await cubit.watch(reciter: remoteReciter, surah: surah2);

      expect(cubit.state.canDownload, isTrue);
      expect(cubit.state.isInstalled, isFalse);
      expect(cubit.state.download.status, PackStatus.idle);

      await cubit.download();

      // No pumping: `download` reads its own result back, so the control is
      // settled the moment it returns.
      expect(cubit.state.download.status, PackStatus.installed);
      expect(cubit.state.isInstalled, isTrue);
      expect(cubit.state.installed!.bytes, greaterThan(0));
    },
  );

  test(
    'deleting it frees the surah and the control offers the download again',
    () async {
      final AudioPackCubit cubit = open();
      await cubit.watch(reciter: remoteReciter, surah: surah2);
      await cubit.download();
      await pumpEventQueue();

      await cubit.delete();
      await pumpEventQueue();

      expect(cubit.state.isInstalled, isFalse);
      expect(cubit.state.download.status, PackStatus.idle);
      expect(cubit.state.canDownload, isTrue);
    },
  );

  test('a failed download leaves the control in a retryable state, not an '
      'error screen', () async {
    fetcher.failWith = const SocketException('offline');
    final AudioPackCubit cubit = open();
    await cubit.watch(reciter: remoteReciter, surah: surah2);

    await cubit.download();
    await pumpEventQueue();

    expect(cubit.state.download.status, PackStatus.failed);
    expect(cubit.state.isInstalled, isFalse);
    expect(cubit.state.canDownload, isTrue);
  });

  test(
    'an install made before the screen opened is seen straight away',
    () async {
      final AudioPackCubit first = open();
      await first.watch(reciter: remoteReciter, surah: surah2);
      await first.download();
      await pumpEventQueue();

      final AudioPackCubit second = open();
      await second.watch(reciter: remoteReciter, surah: surah2);

      expect(second.state.isInstalled, isTrue);
    },
  );
}
