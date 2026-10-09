import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/state/load_status.dart';
import 'package:mirqat/data/models/audio_pack.dart';
import 'package:mirqat/features/settings/cubit/mushaf_download_cubit.dart';
import 'package:mirqat/features/settings/cubit/mushaf_download_state.dart';
import 'package:mirqat/services/audio/audio_pack_service.dart';
import 'package:mirqat/services/audio/audio_storage.dart';
import 'package:mirqat/services/audio/pack_fetcher.dart';

import '../quran_db_fixtures.dart';

/// One zip holding every surah's clips: the unpacker writes only the entries
/// named for the surah it asked for, so the same bytes serve all three.
List<int> packZip() {
  final Archive archive = Archive();
  for (int surah = 1; surah <= 3; surah++) {
    for (int ayah = 0; ayah <= 3; ayah++) {
      final String name =
          '${surah.toString().padLeft(3, '0')}'
          '${ayah.toString().padLeft(3, '0')}.mp3';
      final List<int> bytes = utf8.encode('mp3:$name');
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }
  }
  return ZipEncoder().encode(archive);
}

/// Bundled reciter `b` of the fixture catalog, extended by the manifest with
/// all three surahs of the fixture mushaf. `a` stays bundled-only, with no
/// manifest entry at all.
String manifestJson({required int bytes, required String sha}) =>
    '''
{"schemaVersion":1,"baseUrl":"https://example.invalid/cdn/","mirrors":[],
 "reciters":[{"id":"b","nameAr":"ب","nameEn":"B","riwayah":"hafs",
   "bitrate":64,"version":"1","audioPath":"audio/{id}/{bitrate}/{s3}{a3}.mp3",
   "packPath":"packs/{id}/{bitrate}/{s3}.zip","totalBytes":${bytes * 3},
   "surahs":[{"n":1,"ayahs":3,"bytes":$bytes,"sha256":"$sha"},
             {"n":2,"ayahs":3,"bytes":$bytes,"sha256":"$sha"},
             {"n":3,"ayahs":3,"bytes":$bytes,"sha256":"$sha"}]}]}
''';

class _Fetcher implements PackFetcher {
  _Fetcher(this.bytes);

  final List<int> bytes;
  final List<Uri> fetched = <Uri>[];
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
    destination.parent.createSync(recursive: true);
    destination.writeAsBytesSync(bytes, flush: true);
    onProgress?.call(0.5);
    return destination;
  }

  @override
  Future<void> cancel(String taskId) async {}

  @override
  Future<Map<String, String>> fetchAll({
    required List<FileRequest> requests,
    bool requiresWiFi = false,
    void Function(double progress)? onProgress,
  }) async => const <String, String>{};

  @override
  Future<void> cancelAll(List<String> taskIds) async {}
}

void main() {
  late Directory stateDir;
  late Directory storageRoot;
  late AudioPackService packs;
  late _Fetcher fetcher;
  late String manifest;

  setUp(() async {
    stateDir = Directory.systemTemp.createTempSync('mirqat_whole_state');
    storageRoot = Directory.systemTemp.createTempSync('mirqat_whole');

    final List<int> zip = packZip();
    manifest = manifestJson(
      bytes: zip.length,
      sha: sha256.convert(zip).toString(),
    );
    fetcher = _Fetcher(zip);
    packs = AudioPackService(
      manifestService: fixtureManifestService(bundled: manifest),
      audioStorage: AudioStorage(
        resolveStorageDirectory: () async => storageRoot,
      ),
      downloadsRepository: await fixtureDownloadsRepository(stateDir),
      quranRepository: fixtureRepository(),
      packFetcher: () => fetcher,
    );
  });

  tearDown(() async {
    await packs.dispose();
    for (final Directory dir in <Directory>[stateDir, storageRoot]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  MushafDownloadCubit open() {
    final MushafDownloadCubit cubit = MushafDownloadCubit(
      packService: packs,
      reciterCatalog: fixtureCatalog(manifest: manifest),
    );
    addTearDown(cubit.close);
    return cubit;
  }

  test('only reciters with something to fetch are listed', () async {
    final MushafDownloadCubit cubit = open();

    await cubit.load();

    expect(cubit.state.status, LoadStatus.ready);
    // `a` is bundled-only: nothing to download, so no row.
    expect(
      cubit.state.reciters.map((ReciterOffline r) => r.reciter.id),
      <String>['b'],
    );
    final ReciterOffline entry = cubit.state.reciters.single;
    // Surahs 1 and 2 ship with `b`; only the third is the manifest's to
    // fetch, and only it is counted or sized.
    expect(entry.pending.surahs, <int>[3]);
    expect(entry.pending.onDevice, 2);
    expect(entry.pending.offered, 3);
    expect(entry.pending.bytes, fetcher.bytes.length);
    expect(entry.isComplete, isFalse);
    expect(cubit.state.anyRunning, isFalse);
  });

  test('a whole-mushaf download leaves nothing to fetch', () async {
    final MushafDownloadCubit cubit = open();
    await cubit.load();

    await cubit.downloadWhole(cubit.state.reciters.single.reciter);

    final ReciterOffline entry = cubit.state.reciters.single;
    expect(entry.run.status, BulkStatus.finished);
    expect(entry.run.done, 1);
    expect(entry.run.failed, isEmpty);
    expect(entry.isComplete, isTrue);
    expect(entry.pending.surahs, isEmpty);
    expect(fetcher.fetched, hasLength(1));
  });

  test('a run that is going is reported as such, with its progress', () async {
    final MushafDownloadCubit cubit = open();
    await cubit.load();

    final Future<void> running = cubit.downloadWhole(
      cubit.state.reciters.single.reciter,
    );
    final MushafDownloadState mid = await cubit.stream.firstWhere(
      (MushafDownloadState s) => s.anyRunning,
    );

    final ReciterOffline entry = mid.reciters.single;
    expect(entry.run.total, 1);
    expect(entry.run.currentSurah, anyOf(isNull, 3));
    await running;
    expect(cubit.state.anyRunning, isFalse);
  });

  test(
    'a surah that will not download is counted, and still streams',
    () async {
      fetcher.failWith = const SocketException('offline');
      final MushafDownloadCubit cubit = open();
      await cubit.load();

      await cubit.downloadWhole(cubit.state.reciters.single.reciter);

      final ReciterOffline entry = cubit.state.reciters.single;
      expect(entry.run.failed, <int>[3]);
      expect(entry.run.done, 0);
      expect(entry.isComplete, isFalse);
      // Nothing was installed, and nothing about reading or streaming changed.
      expect(
        (await packs.installed()).getOrElse(() => const <InstalledPack>[]),
        isEmpty,
      );
    },
  );

  test('freeing a surah elsewhere puts it back into what is pending', () async {
    final MushafDownloadCubit cubit = open();
    await cubit.load();
    await cubit.downloadWhole(cubit.state.reciters.single.reciter);
    expect(cubit.state.reciters.single.isComplete, isTrue);

    await packs.delete(reciterId: 'b', surahNumber: 3, bitrate: 64);
    await cubit.stream
        .firstWhere((MushafDownloadState s) => !s.reciters.single.isComplete)
        .timeout(const Duration(seconds: 5), onTimeout: () => cubit.state);

    expect(cubit.state.reciters.single.pending.surahs, <int>[3]);
  });
}
