// ignore_for_file: experimental_member_use
//
// LockCachingAudioSource carries just_audio's experimental flag; these tests
// assert on the streamed arm, so they name the type on purpose. The reason it
// is used at all is in AudioResolver.

import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mirqat/core/constants/asset_paths.dart';
import 'package:mirqat/core/error/exceptions.dart';
import 'package:mirqat/core/error/failures.dart';
import 'package:mirqat/data/models/app_settings.dart';
import 'package:mirqat/data/models/audio_manifest.dart';
import 'package:mirqat/data/models/reciter.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:mirqat/data/repositories/quran_repository.dart';
import 'package:mirqat/data/repositories/settings_repository.dart';
import 'package:mirqat/services/audio/audio_resolver.dart';
import 'package:mirqat/services/audio/audio_storage.dart';
import 'package:mirqat/services/audio/ayah_duration_service.dart';
import 'package:mirqat/services/audio/session_preambles.dart';
import 'package:path/path.dart' as p;

import '../quran_db_fixtures.dart';

/// Surah 1 of the fixture catalog: three ayahs, basmala counted as ayah 1.
const Surah surah1 = Surah(
  number: 1,
  nameAr: 'س',
  nameEn: 'One',
  ayahCount: 3,
  revelationPlace: RevelationPlace.makkah,
  bismillahMode: BismillahMode.countedAsAyah1,
);

/// Surah 2: three ayahs, and its basmala precedes ayah 1.
const Surah surah2 = Surah(
  number: 2,
  nameAr: 'س',
  nameEn: 'Two',
  ayahCount: 3,
  revelationPlace: RevelationPlace.madinah,
  bismillahMode: BismillahMode.separatePreamble,
);

/// Surah 3: nobody in these fixtures has recorded it.
const Surah surah3 = Surah(
  number: 3,
  nameAr: 'س',
  nameEn: 'Three',
  ayahCount: 3,
  revelationPlace: RevelationPlace.makkah,
  bismillahMode: BismillahMode.separatePreamble,
);

/// Surah 1 ships inside the app, with both preamble clips.
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

/// A bundled reciter whose surah 1 is one whole file cut by a timings file,
/// and who ships no standalone preamble clips.
const Reciter timingsReciter = Reciter(
  id: 't',
  nameAr: 'ت',
  nameEn: 'T',
  audioMode: AudioMode.singleFileWithTimings,
  basePath: 'assets/audio/t',
  bundled: true,
  availableSurahs: <int>[1],
  hasIstiadhah: false,
  hasBismillah: false,
);

/// The manifest as the CDN serves it: reciter `a` extended with surah 2, and
/// `cdn` — a reciter nothing ships — with surahs 1 and 2.
const String cdnManifest = '''
{"schemaVersion":1,"baseUrl":"https://example.invalid/cdn/","mirrors":[],
 "reciters":[
  {"id":"a","nameAr":"أ","nameEn":"A","riwayah":"hafs","bitrate":64,
   "version":"1","audioPath":"audio/{id}/{bitrate}/{s3}{a3}.mp3",
   "packPath":"packs/{id}/{bitrate}/{s3}.zip","totalBytes":10,
   "surahs":[{"n":2,"ayahs":3,"bytes":10,"sha256":"ab"}]},
  {"id":"cdn","nameAr":"ق","nameEn":"Q","riwayah":"hafs","bitrate":128,
   "version":"1","audioPath":"audio/{id}/{bitrate}/{s3}{a3}.mp3",
   "packPath":"packs/{id}/{bitrate}/{s3}.zip","totalBytes":20,
   "surahs":[{"n":1,"ayahs":3,"bytes":10,"sha256":"cd"},
             {"n":2,"ayahs":3,"bytes":10,"sha256":"ef"}]}]}
''';

/// Three windows, which is every ayah of the fixture surah 1.
const String timingsJson = '''
{"surah":1,"reciter":"t","ayahs":[
  {"number":1,"startMs":0,"endMs":1000},
  {"number":2,"startMs":1000,"endMs":2000},
  {"number":3,"startMs":2000,"endMs":3000}]}
''';

ManifestReciter manifestEntry(String id) => AudioManifest.fromJson(
  jsonDecode(cdnManifest),
  'test',
).reciters.firstWhere((ManifestReciter r) => r.id == id);

String uriOf(AudioSource source) => switch (source) {
  UriAudioSource(uri: final Uri uri) => uri.toString(),
  LockCachingAudioSource(uri: final Uri uri) => uri.toString(),
  _ => throw StateError('No uri on ${source.runtimeType}.'),
};

void main() {
  late Directory storageRoot;

  setUp(() {
    storageRoot = Directory.systemTemp.createTempSync('mirqat_audio');
    addTearDown(() {
      if (storageRoot.existsSync()) storageRoot.deleteSync(recursive: true);
    });
  });

  /// A resolver over the fixture catalog, the CDN manifest and a real (empty)
  /// storage directory.
  AudioResolver resolverFor({
    String manifest = cdnManifest,
    QuranRepository? quran,
  }) => AudioResolver(
    quranRepository: quran ?? fixtureRepository(),
    manifestService: fixtureManifestService(bundled: manifest),
    audioStorage: AudioStorage(
      resolveStorageDirectory: () async => storageRoot,
    ),
  );

  /// Writes the file a pack download would have left for this ayah.
  File downloadAyah({
    required String reciterId,
    required int bitrate,
    required int surah,
    required int ayah,
  }) {
    final File file = File(
      p.join(
        storageRoot.path,
        AssetPaths.downloadedAyahFile(
          reciterId: reciterId,
          bitrate: bitrate,
          surahNumber: surah,
          ayahNumber: ayah,
        ),
      ),
    )..createSync(recursive: true);
    return file..writeAsStringSync('not really an mp3');
  }

  group('the bundled arm', () {
    test('a surah that ships inside the app plays from its asset', () async {
      final SurahAudio audio = await resolverFor().forSurah(
        reciter: bundledReciter.withRemote(manifestEntry('a')),
        surah: surah1,
      );

      expect(uriOf(audio.sourceFor(3)), 'asset:///assets/audio/a/001/003.mp3');
    });

    test(
      'a bundled asset wins even when the manifest offers the same surah',
      () async {
        // Surah 1 is bundled for `a` and the manifest does not carry it; surah 2
        // is the other way round. The same reciter, the same session, two
        // different arms of the chain.
        final Reciter reciter = bundledReciter.withRemote(manifestEntry('a'));
        final AudioResolver resolver = resolverFor();

        final SurahAudio bundled = await resolver.forSurah(
          reciter: reciter,
          surah: surah1,
        );
        final SurahAudio streamed = await resolver.forSurah(
          reciter: reciter,
          surah: surah2,
        );

        expect(uriOf(bundled.sourceFor(1)), startsWith('asset:///'));
        expect(uriOf(streamed.sourceFor(1)), startsWith('https://'));
      },
    );

    test('a bundled single_file_with_timings surah is clipped to the ayah '
        'window', () async {
      final SurahAudio audio = await resolverFor(
        quran: fixtureRepository(
          extraAssets: <String, String>{
            AssetPaths.timingsForSurah('t', 1): timingsJson,
          },
        ),
      ).forSurah(reciter: timingsReciter, surah: surah1);

      final ClippingAudioSource source =
          audio.sourceFor(2) as ClippingAudioSource;

      expect(uriOf(source.child), 'asset:///assets/audio/t/001.mp3');
      expect(source.start, const Duration(milliseconds: 1000));
      expect(source.end, const Duration(milliseconds: 2000));
    });

    test('a bundled timings surah with no timings file refuses the session '
        'rather than guessing windows', () async {
      expect(
        () => resolverFor().forSurah(reciter: timingsReciter, surah: surah1),
        throwsA(isA<SessionConfigException>()),
      );
    });
  });

  group('the downloaded arm', () {
    test('a downloaded ayah plays from disk', () async {
      final File file = downloadAyah(
        reciterId: 'cdn',
        bitrate: 128,
        surah: 2,
        ayah: 3,
      );
      final SurahAudio audio = await resolverFor().forSurah(
        reciter: Reciter.remoteOnly(manifestEntry('cdn')),
        surah: surah2,
      );

      expect(uriOf(audio.sourceFor(3)), Uri.file(file.path).toString());
      expect(uriOf(audio.sourceFor(3)), endsWith('audio/cdn/128/002003.mp3'));
    });

    test('a download of one ayah does not divert the others', () async {
      downloadAyah(reciterId: 'cdn', bitrate: 128, surah: 2, ayah: 3);
      final SurahAudio audio = await resolverFor().forSurah(
        reciter: Reciter.remoteOnly(manifestEntry('cdn')),
        surah: surah2,
      );

      expect(uriOf(audio.sourceFor(3)), startsWith('file://'));
      expect(uriOf(audio.sourceFor(2)), startsWith('https://'));
    });
  });

  group('the streamed arm', () {
    test('an ayah nobody has locally streams from the manifest url, padded to '
        'three digits', () async {
      final SurahAudio audio = await resolverFor().forSurah(
        reciter: Reciter.remoteOnly(manifestEntry('cdn')),
        surah: surah2,
      );

      expect(
        uriOf(audio.sourceFor(3)),
        'https://example.invalid/cdn/audio/cdn/128/002003.mp3',
      );
    });

    test('a streamed ayah caches to the path a pack download would have '
        'written, so the second play is local', () async {
      final SurahAudio audio = await resolverFor().forSurah(
        reciter: Reciter.remoteOnly(manifestEntry('cdn')),
        surah: surah2,
      );

      final LockCachingAudioSource source =
          audio.sourceFor(3) as LockCachingAudioSource;

      expect(
        (await source.cacheFile).path,
        p.join(storageRoot.path, 'audio', 'cdn', '128', '002003.mp3'),
      );
    });

    test(
      'an ayah that is nowhere at all is refused, not silently skipped',
      () async {
        final SurahAudio audio = await resolverFor().forSurah(
          reciter: Reciter.remoteOnly(manifestEntry('cdn')),
          surah: surah3,
        );

        expect(
          () => audio.sourceFor(1),
          throwsA(isA<SessionConfigException>()),
        );
      },
    );

    test('a manifest that never arrived leaves a bundled reciter with only '
        'its bundled surahs', () async {
      final AudioResolver resolver = resolverFor(manifest: emptyManifest);

      final SurahAudio bundled = await resolver.forSurah(
        reciter: bundledReciter,
        surah: surah1,
      );
      final SurahAudio nothing = await resolver.forSurah(
        reciter: bundledReciter,
        surah: surah2,
      );

      expect(uriOf(bundled.sourceFor(1)), startsWith('asset:///'));
      expect(
        () => nothing.sourceFor(1),
        throwsA(isA<SessionConfigException>()),
      );
    });
  });

  group('audio quality', () {
    /// `cdn` at 64 by default, also published at 128.
    const String twoQualities = '''
{"schemaVersion":1,"baseUrl":"https://example.invalid/cdn/","mirrors":[],
 "reciters":[{"id":"cdn","nameAr":"ق","nameEn":"Q","riwayah":"hafs",
   "bitrate":64,"version":"1","audioPath":"audio/{id}/{bitrate}/{s3}{a3}.mp3",
   "packPath":"packs/{id}/{bitrate}/{s3}.zip","totalBytes":20,
   "surahs":[{"n":2,"ayahs":3,"bytes":10,"sha256":"ab",
              "qualities":{"128":{"bytes":20,"sha256":"cd"}}}]}]}
''';

    Reciter reciterOf(String manifest) => Reciter.remoteOnly(
      AudioManifest.fromJson(jsonDecode(manifest), 'test').reciters.single,
    );

    AudioResolver resolverWithQuality(String manifest, AudioQuality quality) =>
        AudioResolver(
          quranRepository: fixtureRepository(),
          manifestService: fixtureManifestService(bundled: manifest),
          audioStorage: AudioStorage(
            resolveStorageDirectory: () async => storageRoot,
          ),
          settingsRepository: _Settings(AppSettings(audioQuality: quality)),
        );

    test(
      'a chosen quality the reciter publishes is the one streamed',
      () async {
        final SurahAudio audio = await resolverWithQuality(
          twoQualities,
          AudioQuality.high,
        ).forSurah(reciter: reciterOf(twoQualities), surah: surah2);

        expect(audio.bitrate, 128);
        expect(uriOf(audio.sourceFor(1)), contains('/128/'));
      },
    );

    test('a quality the reciter does not publish falls back to theirs, rather '
        'than failing', () async {
      final SurahAudio audio = await resolverWithQuality(
        twoQualities,
        AudioQuality.low,
      ).forSurah(reciter: reciterOf(twoQualities), surah: surah2);

      expect(audio.bitrate, 64);
      expect(uriOf(audio.sourceFor(1)), contains('/64/'));
    });

    test(
      'a surah downloaded at another bitrate still plays from disk',
      () async {
        // Downloaded at 64, and the setting has since moved to 128: changing
        // the preference must not send an offline surah back to the network.
        downloadAyah(reciterId: 'cdn', bitrate: 64, surah: 2, ayah: 1);

        final SurahAudio audio = await resolverWithQuality(
          twoQualities,
          AudioQuality.high,
        ).forSurah(reciter: reciterOf(twoQualities), surah: surah2);

        expect(audio.bitrate, 128);
        expect(audio.isLocal(1), isTrue);
        expect(uriOf(audio.sourceFor(1)), startsWith('file://'));
        expect(uriOf(audio.sourceFor(1)), contains('/64/'));
      },
    );

    test('a deleted surah falls back to streaming with no restart', () async {
      final File file = downloadAyah(
        reciterId: 'cdn',
        bitrate: 64,
        surah: 2,
        ayah: 1,
      );
      final AudioResolver resolver = resolverWithQuality(
        twoQualities,
        AudioQuality.standard,
      );
      final SurahAudio audio = await resolver.forSurah(
        reciter: reciterOf(twoQualities),
        surah: surah2,
      );
      expect(uriOf(audio.sourceFor(1)), startsWith('file://'));

      file.deleteSync();

      // The same SurahAudio, not a new one: resolution asks the filesystem on
      // every lookup, which is what makes "delete" take effect mid-session.
      expect(audio.isLocal(1), isFalse);
      expect(uriOf(audio.sourceFor(1)), startsWith('https://'));
    });
  });

  group('the basmala', () {
    test('a bundled reciter uses its one reciter-level clip, whichever surah '
        'is playing', () async {
      final AudioResolver resolver = resolverFor();
      final Reciter reciter = bundledReciter.withRemote(manifestEntry('a'));

      for (final Surah surah in <Surah>[surah1, surah2]) {
        final SurahAudio audio = await resolver.forSurah(
          reciter: reciter,
          surah: surah,
        );
        expect(
          uriOf(audio.basmala()!),
          'asset:///assets/audio/a/bismillah.mp3',
        );
      }
    });

    test(
      'a manifest reciter takes it from ayah 0 of the surah itself',
      () async {
        final SurahAudio audio = await resolverFor().forSurah(
          reciter: Reciter.remoteOnly(manifestEntry('cdn')),
          surah: surah2,
        );

        expect(
          uriOf(audio.basmala()!),
          'https://example.invalid/cdn/audio/cdn/128/002000.mp3',
        );
      },
    );

    test('a downloaded basmala plays from disk like any other ayah', () async {
      downloadAyah(reciterId: 'cdn', bitrate: 128, surah: 2, ayah: 0);
      final SurahAudio audio = await resolverFor().forSurah(
        reciter: Reciter.remoteOnly(manifestEntry('cdn')),
        surah: surah2,
      );

      expect(uriOf(audio.basmala()!), endsWith('audio/cdn/128/002000.mp3'));
      expect(uriOf(audio.basmala()!), startsWith('file://'));
    });

    test('a manifest that declares no basmala for a surah is believed, so a '
        'session never opens on a 404', () async {
      const String declaresNone = '''
{"schemaVersion":1,"baseUrl":"https://example.invalid/cdn/","mirrors":[],
 "reciters":[{"id":"cdn","nameAr":"ق","nameEn":"Q","riwayah":"hafs",
   "bitrate":128,"version":"1","audioPath":"audio/{id}/{bitrate}/{s3}{a3}.mp3",
   "packPath":"packs/{id}/{bitrate}/{s3}.zip","totalBytes":20,
   "surahs":[{"n":2,"ayahs":3,"bytes":10,"sha256":"ef",
              "hasBasmala":false}]}]}
''';
      final ManifestReciter entry = AudioManifest.fromJson(
        jsonDecode(declaresNone),
        'test',
      ).reciters.single;
      final Reciter reciter = Reciter.remoteOnly(entry);

      final SurahAudio audio = await resolverFor(
        manifest: declaresNone,
      ).forSurah(reciter: reciter, surah: surah2);

      expect(audio.basmala(), isNull);
      // And the preamble is not queued either, so nothing asks the resolver
      // for a clip it just said does not exist.
      expect(reciter.hasBasmala(2), isFalse);
      expect(
        SessionPreambles.forSession(
          surah: surah2,
          reciter: reciter,
          istiadhahEnabled: false,
        ).bismillah,
        isFalse,
      );
      // The ayahs themselves are untouched by the declaration.
      expect(uriOf(audio.sourceFor(1)), endsWith('002001.mp3'));
    });

    test('a manifest that declares a basmala keeps it', () async {
      const String declaresOne = '''
{"schemaVersion":1,"baseUrl":"https://example.invalid/cdn/","mirrors":[],
 "reciters":[{"id":"cdn","nameAr":"ق","nameEn":"Q","riwayah":"hafs",
   "bitrate":128,"version":"1","audioPath":"audio/{id}/{bitrate}/{s3}{a3}.mp3",
   "packPath":"packs/{id}/{bitrate}/{s3}.zip","totalBytes":20,
   "surahs":[{"n":2,"ayahs":3,"bytes":10,"sha256":"ef",
              "hasBasmala":true}]}]}
''';
      final Reciter reciter = Reciter.remoteOnly(
        AudioManifest.fromJson(jsonDecode(declaresOne), 'test').reciters.single,
      );

      final SurahAudio audio = await resolverFor(
        manifest: declaresOne,
      ).forSurah(reciter: reciter, surah: surah2);

      expect(uriOf(audio.basmala()!), endsWith('002000.mp3'));
      expect(reciter.hasBasmala(2), isTrue);
    });

    test('a reciter with neither a clip nor the surah has none', () async {
      final SurahAudio audio = await resolverFor(
        quran: fixtureRepository(
          extraAssets: <String, String>{
            AssetPaths.timingsForSurah('t', 1): timingsJson,
          },
        ),
      ).forSurah(reciter: timingsReciter, surah: surah1);

      expect(audio.basmala(), isNull);
    });

    test('a manifest reciter on a separate-basmala surah gets the preamble '
        'the bundled reciter gets', () {
      final Reciter remote = Reciter.remoteOnly(manifestEntry('cdn'));

      expect(remote.hasBismillah, isFalse);
      expect(remote.hasBasmala(2), isTrue);
      expect(
        SessionPreambles.forSession(
          surah: surah2,
          reciter: remote,
          istiadhahEnabled: true,
        ).bismillah,
        isTrue,
      );
      // Al-Fatiha's basmala *is* ayah 1, and surah 3's audio does not exist
      // for this reciter.
      expect(remote.hasBasmala(3), isFalse);
      expect(
        SessionPreambles.forSession(
          surah: surah1,
          reciter: remote,
          istiadhahEnabled: true,
        ).bismillah,
        isFalse,
      );
    });

    test('a session that picks a surah up part-way opens with no basmala', () {
      // The basmala opens the surah. Ayah 120 is not its opening, and a page
      // in the middle of a surah is where most sessions now start.
      final Reciter remote = Reciter.remoteOnly(manifestEntry('cdn'));
      SessionPreambles at(int ayah) => SessionPreambles.forSession(
        surah: surah2,
        reciter: remote,
        istiadhahEnabled: true,
        startAyah: ayah,
      );
      expect(at(1).bismillah, isTrue);
      expect(at(2).bismillah, isFalse);
      expect(at(120).bismillah, isFalse);
      // The isti'adhah is for beginning to recite, wherever that is.
      expect(at(120).istiadhah, at(1).istiadhah);
    });
  });

  group('what is on the device', () {
    test('a bundled surah is local; a streamed one is not', () async {
      final AudioResolver resolver = resolverFor();
      final Reciter reciter = bundledReciter.withRemote(manifestEntry('a'));

      final SurahAudio bundled = await resolver.forSurah(
        reciter: reciter,
        surah: surah1,
      );
      final SurahAudio streamed = await resolver.forSurah(
        reciter: reciter,
        surah: surah2,
      );

      expect(bundled.isLocal(1), isTrue);
      expect(streamed.isLocal(1), isFalse);
    });

    test('a downloaded ayah is local, ayah by ayah', () async {
      downloadAyah(reciterId: 'cdn', bitrate: 128, surah: 2, ayah: 2);
      final SurahAudio audio = await resolverFor().forSurah(
        reciter: Reciter.remoteOnly(manifestEntry('cdn')),
        surah: surah2,
      );

      expect(audio.isLocal(2), isTrue);
      expect(audio.isLocal(3), isFalse);
    });
  });

  group('the duration probe', () {
    test('a streamed surah is left unmeasured rather than downloaded to time '
        'it', () async {
      // No player is supplied: if the service probed anything it would have to
      // build one, which has no implementation under `flutter test`. Getting
      // an empty map back *is* the assertion that nothing was fetched.
      final AyahDurationService durations = AyahDurationService(
        quranRepository: fixtureRepository(),
        audioResolver: resolverFor(),
      );
      addTearDown(durations.dispose);

      expect(
        await durations.durationsFor(
          reciter: Reciter.remoteOnly(manifestEntry('cdn')),
          surah: surah2,
        ),
        isEmpty,
      );
    });

    test('a bundled timings surah is measured from its timings file, with no '
        'probing at all', () async {
      final QuranRepository quran = fixtureRepository(
        extraAssets: <String, String>{
          AssetPaths.timingsForSurah('t', 1): timingsJson,
        },
      );
      final AyahDurationService durations = AyahDurationService(
        quranRepository: quran,
        audioResolver: resolverFor(quran: quran),
      );
      addTearDown(durations.dispose);

      expect(
        await durations.durationsFor(reciter: timingsReciter, surah: surah1),
        <int, Duration>{
          1: const Duration(seconds: 1),
          2: const Duration(seconds: 1),
          3: const Duration(seconds: 1),
        },
      );
    });
  });

  group('the fixed clips', () {
    test('the istiadhah is one bundled clip per reciter, or nothing', () async {
      final AudioResolver resolver = resolverFor();

      expect(
        uriOf(
          (await resolver.forSurah(
            reciter: bundledReciter,
            surah: surah1,
          )).istiadhah()!,
        ),
        'asset:///assets/audio/a/istiadhah.mp3',
      );
      // Nothing in the manifest carries an isti'adhah: it is not part of any
      // surah, so a manifest-only reciter has none.
      expect(
        (await resolver.forSurah(
          reciter: Reciter.remoteOnly(manifestEntry('cdn')),
          surah: surah2,
        )).istiadhah(),
        isNull,
      );
    });

    test(
      'the spacer is the bundled sample-exact WAV, never a request',
      () async {
        final SurahAudio audio = await resolverFor().forSurah(
          reciter: Reciter.remoteOnly(manifestEntry('cdn')),
          surah: surah2,
        );

        expect(uriOf(audio.spacer()), 'asset:///${AssetPaths.silenceSpacer}');
      },
    );
  });

  group('AudioStorage', () {
    test(
      'answers nothing before it is prepared, rather than guessing a path',
      () {
        final AudioStorage storage = AudioStorage(
          resolveStorageDirectory: () async => storageRoot,
        );

        expect(storage.root, isNull);
        expect(
          storage.fileFor(
            reciterId: 'cdn',
            bitrate: 64,
            surahNumber: 1,
            ayahNumber: 1,
          ),
          isNull,
        );
      },
    );

    test('a platform with nowhere to write is not a failure — it is no '
        'downloads', () async {
      final AudioStorage storage = AudioStorage(
        resolveStorageDirectory: () async =>
            throw UnsupportedError('no storage here'),
      );
      await storage.prepare();

      expect(storage.root, isNull);
      expect(
        storage.downloadedFileFor(
          reciterId: 'cdn',
          bitrate: 64,
          surahNumber: 1,
          ayahNumber: 1,
        ),
        isNull,
      );
    });

    test(
      'the pack layout runs surah and ayah together, basmala as ayah 000',
      () async {
        final AudioStorage storage = AudioStorage(
          resolveStorageDirectory: () async => storageRoot,
        );
        await storage.prepare();

        expect(
          storage
              .fileFor(
                reciterId: 'cdn',
                bitrate: 64,
                surahNumber: 2,
                ayahNumber: 0,
              )!
              .path,
          p.join(storageRoot.path, 'audio', 'cdn', '64', '002000.mp3'),
        );
      },
    );
  });
}

/// Settings that never change, for the quality cases.
class _Settings implements SettingsRepository {
  const _Settings(this.settings);

  final AppSettings settings;

  @override
  Future<Either<Failure, AppSettings>> read() async =>
      Right<Failure, AppSettings>(settings);

  @override
  Future<Either<Failure, AppSettings>> save(AppSettings settings) async =>
      Right<Failure, AppSettings>(settings);
}
