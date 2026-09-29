import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mirqat/core/error/failures.dart';
import 'package:mirqat/data/models/audio_manifest.dart';
import 'package:mirqat/data/models/audio_pack.dart';
import 'package:mirqat/data/models/reciter.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:mirqat/services/audio/audio_pack_service.dart';
import 'package:mirqat/services/audio/audio_resolver.dart';
import 'package:mirqat/services/audio/audio_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:mirqat/admin/services/pack_publisher.dart';
import 'package:mirqat/services/audio/pack_fetcher.dart';
import 'package:path/path.dart' as p;

import '../quran_db_fixtures.dart';

/// Al-Ikhlas: 4 ayahs, and its basmala precedes ayah 1.
const Surah ikhlas = Surah(
  number: 112,
  nameAr: 'الإخلاص',
  nameEn: 'Al-Ikhlas',
  ayahCount: 4,
  revelationPlace: RevelationPlace.makkah,
  bismillahMode: BismillahMode.separatePreamble,
);

/// Bytes that pass the generator's "is this really an mp3" guard.
List<int> clip(int seed) => <int>[
  ...utf8.encode('ID3'),
  0x03,
  0,
  0,
  0,
  0,
  0,
  0,
  for (int i = 0; i < 2048; i++) (seed + i) % 251,
];

/// `tool/build_manifest.py` writes what the app reads, and this is the seam
/// between them: the generator runs for real against the shipped `quran.db`,
/// and its manifest and its packs then go through `AudioManifest`,
/// `AudioResolver` and `AudioPackService` untouched.
///
/// Skipped where there is no `python3`: the tool is a developer's, not the
/// app's, and a machine without it can still run every other test.
void main() {
  final bool hasPython =
      Process.runSync('which', <String>['python3']).exitCode == 0;

  group(
    'tool/build_manifest.py',
    skip: hasPython ? null : 'python3 is not on PATH',
    () {
      late Directory cdn;
      late Directory storageRoot;
      late Directory stateDir;

      setUp(() {
        cdn = Directory.systemTemp.createTempSync('mirqat_cdn');
        storageRoot = Directory.systemTemp.createTempSync('mirqat_cdn_store');
        stateDir = Directory.systemTemp.createTempSync('mirqat_cdn_state');

        final Directory bitrate = Directory(
          p.join(cdn.path, 'audio', 'shaheen', '64'),
        )..createSync(recursive: true);
        File(
          p.join(cdn.path, 'audio', 'shaheen', 'reciter.json'),
        ).writeAsStringSync(
          jsonEncode(<String, String>{
            'nameAr': 'أحمد خليل شاهين',
            'nameEn': 'Ahmed Khalil Shaheen',
            'riwayah': 'hafs',
            'version': '1',
          }),
        );
        // Al-Ikhlas with its basmala, Al-Fatiha without one — the two shapes
        // the generator has to tell apart, and it reads which is which from
        // quran.db.
        for (int ayah = 0; ayah <= 4; ayah++) {
          File(
            p.join(bitrate.path, '112${ayah.toString().padLeft(3, '0')}.mp3'),
          ).writeAsBytesSync(clip(ayah));
        }
        for (int ayah = 1; ayah <= 7; ayah++) {
          File(
            p.join(bitrate.path, '001${ayah.toString().padLeft(3, '0')}.mp3'),
          ).writeAsBytesSync(clip(100 + ayah));
        }
      });

      tearDown(() async {
        for (final Directory dir in <Directory>[cdn, storageRoot, stateDir]) {
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        }
      });

      ProcessResult runGenerator({List<String> extra = const <String>[]}) =>
          Process.runSync('python3', <String>[
            'tool/build_manifest.py',
            '--root',
            cdn.path,
            ...extra,
          ]);

      String manifestText() =>
          File(p.join(cdn.path, 'manifest.json')).readAsStringSync();

      AudioManifest generated() {
        final ProcessResult result = runGenerator();
        expect(
          result.exitCode,
          0,
          reason: 'generator failed:\n${result.stdout}\n${result.stderr}',
        );
        return AudioManifest.fromJson(jsonDecode(manifestText()), 'generated');
      }

      test('the generated manifest is one the app accepts, carrying the surah '
          'facts the tool read out of quran.db', () {
        final AudioManifest manifest = generated();

        expect(manifest.schemaVersion, AudioManifest.supportedSchemaVersion);
        final ManifestReciter reciter = manifest.reciters.single;
        expect(reciter.id, 'shaheen');
        expect(reciter.nameAr, 'أحمد خليل شاهين');
        expect(reciter.bitrate, 64);
        expect(reciter.surahs.map((ManifestSurah s) => s.number), <int>[
          1,
          112,
        ]);

        // Al-Fatiha's basmala *is* ayah 1, so nothing is declared; Al-Ikhlas
        // ships a 000 file, so it declares true.
        expect(reciter.surah(1)!.ayahs, 7);
        expect(reciter.surah(1)!.hasBasmala, isNull);
        expect(reciter.surah(112)!.ayahs, 4);
        expect(reciter.surah(112)!.hasBasmala, isTrue);

        expect(
          manifest.urlFor(reciter.audioPathFor(112, 0)).toString(),
          endsWith('/audio/shaheen/64/112000.mp3'),
        );
        expect(
          manifest.urlFor(reciter.packPathFor(112)).toString(),
          endsWith('/packs/shaheen/64/112.zip'),
        );
      });

      test('a generated pack installs through the real download path, digest '
          'and all, and then plays from disk', () async {
        final AudioManifest manifest = generated();
        final ManifestReciter entry = manifest.reciters.single;
        final Reciter reciter = Reciter.remoteOnly(
          entry,
          surahs: <int>{1, 112},
        );

        final File pack = File(
          p.join(cdn.path, 'packs', 'shaheen', '64', '112.zip'),
        );
        expect(pack.existsSync(), isTrue);
        // The manifest's numbers describe that file exactly — this is what
        // AudioPackService verifies before it installs anything.
        expect(pack.lengthSync(), entry.surah(112)!.bytes);

        final AudioStorage storage = AudioStorage(
          resolveStorageDirectory: () async => storageRoot,
        );
        final AudioPackService packs = AudioPackService(
          manifestService: fixtureManifestService(bundled: manifestText()),
          audioStorage: storage,
          downloadsRepository: await fixtureDownloadsRepository(stateDir),
          packFetcher: () => _FileFetcher(pack),
        );
        addTearDown(packs.dispose);

        final Either<Failure, InstalledPack> installed = await packs.download(
          reciter: reciter,
          surahNumber: 112,
        );
        expect(installed.isRight(), isTrue, reason: '$installed');

        final SurahAudio audio = await AudioResolver(
          quranRepository: fixtureRepository(),
          manifestService: fixtureManifestService(bundled: manifestText()),
          audioStorage: storage,
        ).forSurah(reciter: reciter, surah: ikhlas);

        for (int ayah = 1; ayah <= ikhlas.ayahCount; ayah++) {
          expect(audio.isLocal(ayah), isTrue, reason: 'ayah $ayah');
          expect(
            (audio.sourceFor(ayah) as UriAudioSource).uri.toString(),
            startsWith('file://'),
          );
        }
        expect(
          (audio.basmala()! as UriAudioSource).uri.toString(),
          endsWith('112000.mp3'),
        );
      });

      test('a rebuild is byte-identical, so --check passes and a sync has '
          'nothing to re-upload', () {
        generated();
        final List<int> firstPack = File(
          p.join(cdn.path, 'packs', 'shaheen', '64', '112.zip'),
        ).readAsBytesSync();

        final ProcessResult check = runGenerator(extra: <String>['--check']);
        expect(check.exitCode, 0, reason: '${check.stdout}${check.stderr}');

        generated();
        expect(
          File(
            p.join(cdn.path, 'packs', 'shaheen', '64', '112.zip'),
          ).readAsBytesSync(),
          firstPack,
        );
      });

      test('a reciter published at two bitrates gets a qualities entry the '
          'app can choose from', () {
        // A second encode of the same surah, as a CDN offering 128 kbps would
        // have it.
        final Directory high = Directory(
          p.join(cdn.path, 'audio', 'shaheen', '128'),
        )..createSync(recursive: true);
        for (int ayah = 0; ayah <= 4; ayah++) {
          File(
            p.join(high.path, '112${ayah.toString().padLeft(3, '0')}.mp3'),
          ).writeAsBytesSync(clip(200 + ayah));
        }
        for (int ayah = 1; ayah <= 7; ayah++) {
          File(
            p.join(high.path, '001${ayah.toString().padLeft(3, '0')}.mp3'),
          ).writeAsBytesSync(clip(300 + ayah));
        }

        final AudioManifest manifest = generated();
        final ManifestReciter reciter = manifest.reciters.single;

        // The lower bitrate is the reciter's own, the higher one an extra.
        expect(reciter.bitrate, 64);
        expect(reciter.bitratesFor(112), <int>[64, 128]);

        final PackVariant high128 = reciter.variantFor(
          112,
          preferredBitrate: 128,
        )!;
        expect(high128.bitrate, 128);
        expect(high128.sha256, isNotEmpty);
        expect(
          high128.sha256,
          isNot(reciter.variantFor(112)!.sha256),
          reason: 'a different encode is a different file',
        );
        expect(
          File(
            p.join(cdn.path, 'packs', 'shaheen', '128', '112.zip'),
          ).lengthSync(),
          high128.bytes,
        );

        // And a quality nobody published falls back rather than failing.
        expect(reciter.variantFor(112, preferredBitrate: 32)!.bitrate, 64);
      });

      test('a pack the admin tool built is kept, not rebuilt — the two tools '
          'must not disagree about a surah that has not changed', () {
        // Two zip libraries do not agree on bytes they both consider
        // irrelevant (the "created by" byte, the attribute encoding), so a
        // rebuild here would change the digest without changing a sample of
        // audio — which reads downstream as a new recording.
        final Directory bitrate = Directory(
          p.join(cdn.path, 'audio', 'shaheen', '64'),
        );
        final List<File> segments = bitrate
            .listSync()
            .whereType<File>()
            .where((File f) => p.basename(f.path).startsWith('112'))
            .toList();
        final List<int> pack = PackPublisher().buildPack(segments);
        final File packFile = File(
          p.join(cdn.path, 'packs', 'shaheen', '64', '112.zip'),
        )..createSync(recursive: true);
        packFile.writeAsBytesSync(pack);

        final AudioManifest manifest = generated();

        expect(
          manifest.reciters.single.surah(112)!.sha256,
          sha256.convert(pack).toString(),
        );
        expect(packFile.readAsBytesSync(), pack, reason: 'left untouched');
      });

      test('a pack holding the wrong files is rebuilt', () {
        final File packFile = File(
          p.join(cdn.path, 'packs', 'shaheen', '64', '112.zip'),
        )..createSync(recursive: true);
        packFile.writeAsBytesSync(
          PackPublisher().buildPack(<File>[
            File(p.join(cdn.path, 'audio', 'shaheen', '64', '112001.mp3')),
          ]),
        );
        final List<int> before = packFile.readAsBytesSync();

        generated();

        expect(packFile.readAsBytesSync(), isNot(before));
      });

      test(
        'a surah missing an ayah is refused, and no manifest is written',
        () {
          File(
            p.join(cdn.path, 'audio', 'shaheen', '64', '112003.mp3'),
          ).deleteSync();

          final ProcessResult result = runGenerator();

          expect(result.exitCode, isNot(0));
          expect('${result.stderr}', contains('missing'));
          expect(File(p.join(cdn.path, 'manifest.json')).existsSync(), isFalse);
        },
      );

      test('a basmala file for a surah whose basmala is ayah 1 is refused', () {
        File(
          p.join(cdn.path, 'audio', 'shaheen', '64', '001000.mp3'),
        ).writeAsBytesSync(clip(9));

        final ProcessResult result = runGenerator();

        expect(result.exitCode, isNot(0));
        expect('${result.stderr}', contains('first_ayah'));
      });
    },
  );
}

/// Serves a file already on disk — the pack the generator just wrote.
class _FileFetcher implements PackFetcher {
  _FileFetcher(this.source);

  final File source;

  @override
  Future<File> fetch({
    required Uri url,
    required File destination,
    required String taskId,
    bool requiresWiFi = false,
    void Function(double progress)? onProgress,
  }) async {
    destination.parent.createSync(recursive: true);
    source.copySync(destination.path);
    return destination;
  }

  @override
  Future<void> cancel(String taskId) async {}

  @override
  Future<Map<String, String>> fetchAll({
    required List<FileRequest> requests,
    bool requiresWiFi = false,
    void Function(double progress)? onProgress,
  }) async {
    for (final FileRequest request in requests) {
      request.destination.parent.createSync(recursive: true);
      source.copySync(request.destination.path);
    }
    return const <String, String>{};
  }

  @override
  Future<void> cancelAll(List<String> taskIds) async {}
}
