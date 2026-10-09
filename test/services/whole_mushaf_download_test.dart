import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/data/models/audio_manifest.dart';
import 'package:mirqat/data/models/audio_pack.dart';
import 'package:mirqat/data/models/reciter.dart';
import 'package:mirqat/services/audio/audio_pack_service.dart';
import 'package:mirqat/services/audio/audio_storage.dart';
import 'package:mirqat/services/audio/pack_fetcher.dart';

import '../quran_db_fixtures.dart';

/// One zip holding every surah's clips. The unpacker writes only the entries
/// whose name is the surah it asked for, so the same bytes — and so the same
/// declared size and digest — serve every surah in the manifest. That is what
/// lets a test about a run of ten downloads stay about the run.
List<int> packZip(int surahs, int ayahs) {
  final Archive archive = Archive();
  for (int surah = 1; surah <= surahs; surah++) {
    for (int ayah = 0; ayah <= ayahs; ayah++) {
      final String name =
          '${surah.toString().padLeft(3, '0')}'
          '${ayah.toString().padLeft(3, '0')}.mp3';
      final List<int> bytes = utf8.encode('mp3:$name');
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }
  }
  return ZipEncoder().encode(archive);
}

/// A reciter offering [surahs] surahs of [ayahs] ayahs each, every one at the
/// same declared size and digest.
String manifestFor({
  required int surahs,
  required int ayahs,
  required int bytes,
  required String sha,
}) {
  final String entries = <String>[
    for (int n = 1; n <= surahs; n++)
      '{"n":$n,"ayahs":$ayahs,"bytes":$bytes,"sha256":"$sha"}',
  ].join(',');
  return '''
{"schemaVersion":1,"baseUrl":"https://example.invalid/cdn/","mirrors":[],
 "reciters":[{"id":"cdn","nameAr":"ق","nameEn":"Q","riwayah":"hafs",
   "bitrate":64,"version":"1","audioPath":"audio/{id}/{bitrate}/{s3}{a3}.mp3",
   "packPath":"packs/{id}/{bitrate}/{s3}.zip","totalBytes":${bytes * surahs},
   "surahs":[$entries]}]}
''';
}

/// Serves the pack for every request, unless told to refuse — and lets a test
/// reach in part-way through a run.
class _Fetcher implements PackFetcher {
  _Fetcher(this.bytes);

  final List<int> bytes;
  final List<Uri> fetched = <Uri>[];
  final List<String> cancelled = <String>[];

  /// Thrown instead of serving, for a CDN that is not answering.
  Object? failWith;

  /// Called before each pack is served, with how many have been asked for so
  /// far. What a test uses to cancel a run from inside it.
  Future<void> Function(int count)? onFetch;

  @override
  Future<File> fetch({
    required Uri url,
    required File destination,
    required String taskId,
    bool requiresWiFi = false,
    void Function(double progress)? onProgress,
  }) async {
    fetched.add(url);
    await onFetch?.call(fetched.length);
    final Object? failure = failWith;
    if (failure != null) throw failure;
    destination.parent.createSync(recursive: true);
    destination.writeAsBytesSync(bytes, flush: true);
    onProgress?.call(1);
    return destination;
  }

  @override
  Future<void> cancel(String taskId) async => cancelled.add(taskId);

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

  setUp(() {
    stateDir = Directory.systemTemp.createTempSync('mirqat_whole_state');
    storageRoot = Directory.systemTemp.createTempSync('mirqat_whole');
  });

  tearDown(() {
    for (final Directory dir in <Directory>[stateDir, storageRoot]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  Future<({AudioPackService service, Reciter reciter, _Fetcher fetcher})>
  serviceFor({int surahs = 3, int ayahs = 3}) async {
    final List<int> zip = packZip(surahs, ayahs);
    final String manifestJson = manifestFor(
      surahs: surahs,
      ayahs: ayahs,
      bytes: zip.length,
      sha: sha256.convert(zip).toString(),
    );
    final _Fetcher fetcher = _Fetcher(zip);
    final AudioPackService service = AudioPackService(
      manifestService: fixtureManifestService(bundled: manifestJson),
      audioStorage: AudioStorage(
        resolveStorageDirectory: () async => storageRoot,
      ),
      downloadsRepository: await fixtureDownloadsRepository(stateDir),
      packFetcher: () => fetcher,
    );
    addTearDown(service.dispose);

    return (
      service: service,
      reciter: Reciter.remoteOnly(
        AudioManifest.fromJson(
          jsonDecode(manifestJson),
          'test',
        ).reciters.single,
      ),
      fetcher: fetcher,
    );
  }

  group('what a whole-mushaf download would cost', () {
    test('everything offered, at the size the manifest declares', () async {
      final service = await serviceFor();

      final PendingDownloads plan = (await service.service.pending(
        service.reciter,
      )).getOrElse(() => const PendingDownloads.none('cdn'));

      expect(plan.surahs, <int>[1, 2, 3]);
      expect(plan.offered, 3);
      expect(plan.onDevice, 0);
      expect(plan.bytes, service.fetcher.bytes.length * 3);
      expect(plan.isComplete, isFalse);
    });

    test('a surah already on the device is not asked for again', () async {
      final service = await serviceFor();
      await service.service.download(reciter: service.reciter, surahNumber: 2);

      final PendingDownloads plan = (await service.service.pending(
        service.reciter,
      )).getOrElse(() => const PendingDownloads.none('cdn'));

      expect(plan.surahs, <int>[1, 3]);
      expect(plan.onDevice, 1);
    });

    test(
      'a bundled surah counts as on the device, and is never fetched',
      () async {
        final service = await serviceFor();
        // The same reciter, with surah 1 shipped in the app.
        final Reciter bundled = const Reciter(
          id: 'cdn',
          nameAr: 'ق',
          nameEn: 'Q',
          audioMode: AudioMode.perAyahFiles,
          basePath: 'assets/audio/cdn',
          bundled: true,
          availableSurahs: <int>[1],
          hasIstiadhah: true,
          hasBismillah: true,
        ).withRemote(service.reciter.remote!);

        final PendingDownloads plan = (await service.service.pending(
          bundled,
        )).getOrElse(() => const PendingDownloads.none('cdn'));

        expect(plan.surahs, <int>[2, 3]);
        expect(plan.onDevice, 1);
        expect(plan.offered, 3);
      },
    );

    test(
      'a stale surah is asked for again: a run wants the current reading',
      () async {
        final service = await serviceFor();
        await service.service.download(
          reciter: service.reciter,
          surahNumber: 2,
        );

        // The reciter re-cuts their recordings: same ids, new version.
        final List<int> zip = packZip(3, 3);
        final String newer = manifestFor(
          surahs: 3,
          ayahs: 3,
          bytes: zip.length,
          sha: sha256.convert(zip).toString(),
        ).replaceAll('"version":"1"', '"version":"9"');
        final AudioPackService second = AudioPackService(
          manifestService: fixtureManifestService(bundled: newer),
          audioStorage: AudioStorage(
            resolveStorageDirectory: () async => storageRoot,
          ),
          downloadsRepository: await fixtureDownloadsRepository(stateDir),
          packFetcher: () => _Fetcher(zip),
        );
        addTearDown(second.dispose);
        await second.reconcile();

        final Reciter reciter = Reciter.remoteOnly(
          AudioManifest.fromJson(jsonDecode(newer), 'test').reciters.single,
        );
        final PendingDownloads plan = (await second.pending(
          reciter,
        )).getOrElse(() => const PendingDownloads.none('cdn'));

        expect(plan.surahs, <int>[1, 2, 3]);
        expect(plan.onDevice, 0);
      },
    );
  });

  group('the run', () {
    test('fetches every surah offered, and records each one', () async {
      final service = await serviceFor();

      final BulkDownload run = (await service.service.downloadWhole(
        reciter: service.reciter,
      )).getOrElse(() => const BulkDownload.idle('cdn'));

      expect(run.status, BulkStatus.finished);
      expect(run.total, 3);
      expect(run.done, 3);
      expect(run.failed, isEmpty);
      expect(service.fetcher.fetched, hasLength(3));

      final List<InstalledPack> installed = (await service.service.installed())
          .getOrElse(() => const <InstalledPack>[]);
      expect(
        installed.map((InstalledPack p) => p.surahNumber).toList()..sort(),
        <int>[1, 2, 3],
      );
      final PendingDownloads plan = (await service.service.pending(
        service.reciter,
      )).getOrElse(() => const PendingDownloads.none('cdn'));
      expect(plan.isComplete, isTrue);
    });

    test('reports its progress surah by surah', () async {
      final service = await serviceFor();
      final List<BulkDownload> seen = <BulkDownload>[];
      final sub = service.service.runChanges.listen(seen.add);
      addTearDown(sub.cancel);

      await service.service.downloadWhole(reciter: service.reciter);
      // The run's stream is a broadcast one: its last few events are
      // delivered after the future that made them completes.
      await pumpEventQueue();

      expect(seen.first.status, BulkStatus.running);
      expect(seen.first.total, 3);
      expect(
        seen.map((BulkDownload r) => r.done),
        containsAllInOrder(<int>[1, 2, 3]),
      );
      expect(seen.last.status, BulkStatus.finished);
      expect(seen.last.progress, 1);
    });

    test('steps over a surah that will not download, and says which', () async {
      final service = await serviceFor(surahs: 10);
      final _Fetcher fetcher = service.fetcher;
      // Only surah 4 refuses: a gap in what the CDN holds, not a lost
      // connection.
      fetcher.onFetch = (int count) async =>
          fetcher.failWith = count == 4 ? const SocketException('nope') : null;

      final BulkDownload run = (await service.service.downloadWhole(
        reciter: service.reciter,
      )).getOrElse(() => const BulkDownload.idle('cdn'));

      expect(run.status, BulkStatus.finished);
      expect(run.done, 9);
      expect(run.failed, <int>[4]);
      expect(fetcher.fetched, hasLength(10));
    });

    test(
      'gives up after three refusals in a row rather than all 114',
      () async {
        final service = await serviceFor(surahs: 10);
        service.fetcher.failWith = const SocketException('offline');

        final BulkDownload run = (await service.service.downloadWhole(
          reciter: service.reciter,
        )).getOrElse(() => const BulkDownload.idle('cdn'));

        expect(run.status, BulkStatus.cancelled);
        expect(run.done, 0);
        expect(run.failed, <int>[1, 2, 3]);
        expect(service.fetcher.fetched, hasLength(3));
      },
    );

    test('a cancelled run stops, and keeps what arrived', () async {
      final service = await serviceFor(surahs: 10);
      final _Fetcher fetcher = service.fetcher;
      fetcher.onFetch = (int count) async {
        if (count == 2) await service.service.cancelWhole('cdn');
      };

      final BulkDownload run = (await service.service.downloadWhole(
        reciter: service.reciter,
      )).getOrElse(() => const BulkDownload.idle('cdn'));

      expect(run.status, BulkStatus.cancelled);
      expect(fetcher.fetched, hasLength(2));
      final List<InstalledPack> installed = (await service.service.installed())
          .getOrElse(() => const <InstalledPack>[]);
      expect(installed, hasLength(2));
    });

    test('a second run while one is going is refused, not queued', () async {
      final service = await serviceFor();
      final _Fetcher fetcher = service.fetcher;
      bool? refused;
      fetcher.onFetch = (int count) async {
        if (count != 1 || refused != null) return;
        refused = (await service.service.downloadWhole(
          reciter: service.reciter,
        )).isLeft();
      };

      await service.service.downloadWhole(reciter: service.reciter);

      expect(refused, isTrue);
      expect(fetcher.fetched, hasLength(3));
    });

    test('nothing left to fetch is a finished run, not a failure', () async {
      final service = await serviceFor();
      await service.service.downloadWhole(reciter: service.reciter);

      final BulkDownload again = (await service.service.downloadWhole(
        reciter: service.reciter,
      )).getOrElse(() => const BulkDownload.idle('cdn'));

      expect(again.status, BulkStatus.finished);
      expect(again.total, 0);
      expect(again.progress, 0);
      expect(service.fetcher.fetched, hasLength(3));
    });
  });
}
