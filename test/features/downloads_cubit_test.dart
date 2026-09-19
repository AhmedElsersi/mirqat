import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/state/load_status.dart';
import 'package:mirqat/data/models/audio_manifest.dart';
import 'package:mirqat/data/models/reciter.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:mirqat/features/settings/cubit/downloads_cubit.dart';
import 'package:mirqat/features/settings/cubit/downloads_state.dart';
import 'package:mirqat/services/audio/audio_pack_service.dart';
import 'package:mirqat/services/audio/audio_storage.dart';
import 'package:mirqat/services/audio/pack_fetcher.dart';
import 'package:path/path.dart' as path;

import '../quran_db_fixtures.dart';

const Surah surah2 = Surah(
  number: 2,
  nameAr: 'س',
  nameEn: 'Two',
  ayahCount: 3,
  revelationPlace: RevelationPlace.madinah,
  bismillahMode: BismillahMode.separatePreamble,
);

/// Reciter `a` of the fixture catalog, extended by the manifest with surah 2.
String manifestJson(int bytes) =>
    '''
{"schemaVersion":1,"baseUrl":"https://example.invalid/cdn/","mirrors":[],
 "reciters":[{"id":"a","nameAr":"أ","nameEn":"A","riwayah":"hafs",
   "bitrate":64,"version":"1","audioPath":"audio/{id}/{bitrate}/{s3}{a3}.mp3",
   "packPath":"packs/{id}/{bitrate}/{s3}.zip","totalBytes":$bytes,
   "surahs":[{"n":2,"ayahs":3,"bytes":$bytes,"sha256":"SHA"}]}]}
''';

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

class _Fetcher implements PackFetcher {
  _Fetcher(this.bytes);

  final List<int> bytes;

  @override
  Future<File> fetch({
    required Uri url,
    required File destination,
    required String taskId,
    bool requiresWiFi = false,
    void Function(double progress)? onProgress,
  }) async {
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
  late AudioPackService packs;
  late String manifest;
  late Reciter reciter;

  setUp(() async {
    stateDir = Directory.systemTemp.createTempSync('mirqat_saved_state');
    storageRoot = Directory.systemTemp.createTempSync('mirqat_saved');

    final List<int> zip = packZip();
    manifest = manifestJson(
      zip.length,
    ).replaceAll('SHA', sha256.convert(zip).toString());

    packs = AudioPackService(
      manifestService: fixtureManifestService(bundled: manifest),
      audioStorage: AudioStorage(
        resolveStorageDirectory: () async => storageRoot,
      ),
      downloadsRepository: await fixtureDownloadsRepository(stateDir),
      packFetcher: () => _Fetcher(zip),
    );
    reciter = bundledReciter.withRemote(
      AudioManifest.fromJson(jsonDecode(manifest), 'test').reciters.single,
    );
  });

  tearDown(() async {
    await packs.dispose();
    for (final Directory dir in <Directory>[stateDir, storageRoot]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  DownloadsCubit open() {
    final DownloadsCubit cubit = DownloadsCubit(
      packService: packs,
      quranRepository: fixtureRepository(),
      reciterCatalog: fixtureCatalog(manifest: manifest),
    );
    addTearDown(cubit.close);
    return cubit;
  }

  test('nothing saved is an empty list, not a failure', () async {
    final DownloadsCubit cubit = open();

    await cubit.load();

    expect(cubit.state.status, LoadStatus.ready);
    expect(cubit.state.saved, isEmpty);
    expect(cubit.state.totalBytes, 0);
    expect(cubit.state.errorMessage, isNull);
  });

  test(
    'a saved surah is listed with its names, its size and its bitrate',
    () async {
      await packs.download(reciter: reciter, surahNumber: 2);
      final DownloadsCubit cubit = open();

      await cubit.load();

      final SavedRecitation saved = cubit.state.saved.single;
      expect(saved.pack.surahNumber, 2);
      expect(saved.surah?.number, 2);
      expect(saved.reciter?.nameAr, 'أ');
      expect(saved.pack.bitrate, 64);
      expect(cubit.state.totalBytes, greaterThan(0));
      expect(cubit.state.totalBytes, saved.pack.bytes);
    },
  );

  test('a download made while the screen is open joins the list', () async {
    final DownloadsCubit cubit = open();
    await cubit.load();
    expect(cubit.state.saved, isEmpty);

    await packs.download(reciter: reciter, surahNumber: 2);
    await pumpEventQueue();

    expect(cubit.state.saved, hasLength(1));
  });

  test('freeing a surah empties the list and deletes the files', () async {
    await packs.download(reciter: reciter, surahNumber: 2);
    final DownloadsCubit cubit = open();
    await cubit.load();

    await cubit.delete(cubit.state.saved.single);
    await pumpEventQueue();

    expect(cubit.state.saved, isEmpty);
    expect(
      Directory(path.join(storageRoot.path, 'audio', 'a', '64')).listSync(),
      isEmpty,
    );
  });

  test(
    'a stale surah is flagged, and re-downloading takes only the stale one',
    () async {
      await packs.download(reciter: reciter, surahNumber: 2);
      final DownloadsCubit cubit = open();
      await cubit.load();
      expect(cubit.state.hasStale, isFalse);

      // The reciter re-cuts the recording: same id, new version.
      final AudioPackService newer = AudioPackService(
        manifestService: fixtureManifestService(
          bundled: manifest.replaceAll('"version":"1"', '"version":"5"'),
        ),
        audioStorage: AudioStorage(
          resolveStorageDirectory: () async => storageRoot,
        ),
        downloadsRepository: await fixtureDownloadsRepository(stateDir),
        packFetcher: () => _Fetcher(packZip()),
      );
      addTearDown(newer.dispose);
      final DownloadsCubit second = DownloadsCubit(
        packService: newer,
        quranRepository: fixtureRepository(),
        reciterCatalog: fixtureCatalog(manifest: manifest),
      );
      addTearDown(second.close);

      await second.load();

      expect(second.state.hasStale, isTrue);
      expect(second.state.saved.single.pack.isStale, isTrue);
    },
  );

  test('a pack whose reciter the manifest has dropped is still listed, and '
      'still deletable', () async {
    await packs.download(reciter: reciter, surahNumber: 2);
    // The same storage, but a catalog and manifest that know nothing of `a`'s
    // remote surahs any more.
    final DownloadsCubit cubit = DownloadsCubit(
      packService: packs,
      quranRepository: fixtureRepository(),
      reciterCatalog: fixtureCatalog(
        reciters: '''
[{"id":"z","nameAr":"ز","nameEn":"Z","audioMode":"per_ayah_files",
  "basePath":"assets/audio/z","availableSurahs":[1]}]
''',
      ),
    );
    addTearDown(cubit.close);

    await cubit.load();

    final SavedRecitation saved = cubit.state.saved.single;
    expect(saved.reciter, isNull);
    expect(saved.pack.reciterId, 'a');

    await cubit.delete(saved);
    await pumpEventQueue();
    expect(cubit.state.saved, isEmpty);
  });
}
