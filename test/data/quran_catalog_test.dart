import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/constants/asset_paths.dart';
import 'package:mirqat/data/datasources/bundle_asset_reader.dart';
import 'package:mirqat/data/datasources/quran_local_data_source.dart';
import 'package:mirqat/data/models/ayah.dart';
import 'package:mirqat/data/models/ayah_timing.dart';
import 'package:mirqat/data/models/memorization_progress.dart';
import 'package:mirqat/data/models/reciter.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:mirqat/core/extensions/arabic_text_extensions.dart';

/// Exercises the loaders against the assets that actually ship, so a file that
/// is missing, undeclared in pubspec.yaml, or out of step with the catalog
/// fails here rather than at playback time.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late QuranLocalDataSource source;

  setUp(() => source = QuranLocalDataSourceImpl(BundleAssetReader()));

  group('surah catalog', () {
    test('loads every entry the catalog holds, in ascending order', () async {
      final List<Surah> surahs = await source.getSurahs();

      // Deliberately no expected count: the catalog grows by adding data, and
      // a test that has to be edited for each new surah is a test that will
      // be edited to match whatever shipped.
      expect(surahs, isNotEmpty);
      expect(
        surahs.map((Surah s) => s.number).toList(),
        orderedEquals(
          (surahs.map((Surah s) => s.number).toList()..sort()).toList(),
        ),
      );
      expect(
        surahs.map((Surah s) => s.number).toSet(),
        hasLength(surahs.length),
        reason: 'the catalog lists a surah twice',
      );

      for (final Surah surah in surahs) {
        expect(surah.number, greaterThan(0));
        expect(surah.ayahCount, greaterThan(0));
        expect(surah.nameAr.trim(), isNotEmpty);
        expect(surah.nameEn.trim(), isNotEmpty);
        expect(
          surah.needsBismillahPreamble,
          surah.bismillahMode == BismillahMode.separatePreamble,
          reason: 'surah ${surah.number} disagrees with its own mode',
        );
      }
    });

    test('Al-Fatiha keeps the numbering its mode implies', () async {
      // The one surah pinned by name, because its bismillah being ayah 1 is
      // what stops it being recited twice — see SessionPreambles.
      final Surah fatiha = await source.getSurah(1);
      expect(fatiha.ayahCount, 7);
      expect(fatiha.revelationPlace, RevelationPlace.makkah);
      expect(fatiha.bismillahMode, BismillahMode.countedAsAyah1);
      expect(fatiha.needsBismillahPreamble, isFalse);
    });

    test('caches, so a second read returns the identical list', () async {
      expect(
        identical(await source.getSurahs(), await source.getSurahs()),
        isTrue,
      );
    });

    test('reports a surah that is not in the catalog', () async {
      final Set<int> known =
          (await source.getSurahs()).map((Surah s) => s.number).toSet();
      final int absent = List<int>.generate(115, (int i) => i + 1)
          .firstWhere((int n) => !known.contains(n));
      await expectLater(source.getSurah(absent), throwsA(isA<Exception>()));
    });
  });

  group('ayah text', () {
    test('loads exactly the ayahs the catalog declares, for every '
        'surah', () async {
      for (final Surah surah in await source.getSurahs()) {
        final List<Ayah> ayahs = await source.getAyahs(surah.number);

        expect(ayahs, hasLength(surah.ayahCount), reason: 'surah ${surah.number}');
        expect(
          ayahs.map((Ayah a) => a.number),
          List<int>.generate(surah.ayahCount, (int i) => i + 1),
          reason: 'surah ${surah.number} is not numbered 1..${surah.ayahCount}',
        );
        for (final Ayah ayah in ayahs) {
          expect(ayah.surahNumber, surah.number);
          expect(ayah.text.trim(), isNotEmpty);
        }
      }
    });

    test('is NFC-normalised, so equal ayahs compare equal', () async {
      for (final Surah surah in await source.getSurahs()) {
        for (final Ayah ayah in await source.getAyahs(surah.number)) {
          expect(
            ayah.text.isArabicNfc,
            isTrue,
            reason:
                'surah ${surah.number} ayah ${ayah.number} is not in NFC '
                'after loading',
          );
        }
      }
    });
  });

  group('reciter catalog', () {
    test('loads the bundled reciter', () async {
      final List<Reciter> reciters = await source.getReciters();

      expect(reciters, isNotEmpty);
      final Reciter reciter = reciters.first;
      expect(reciter.id, 'ahmed_khalil_shaheen');
      expect(reciter.nameAr, 'أحمد خليل شاهين');
      expect(reciter.audioMode, AudioMode.perAyahFiles);
      expect(reciter.bundled, isTrue);
      expect(reciter.hasIstiadhah, isTrue);
      expect(reciter.hasBismillah, isTrue);

      // availableSurahs tracks the catalog, so it is read rather than asserted.
      for (final Surah surah in await source.getSurahs()) {
        expect(
          reciter.hasSurah(surah.number),
          reciter.availableSurahs.contains(surah.number),
        );
      }
      expect(reciter.hasSurah(999), isFalse);
    });

    test('hasBismillah defaults to false when a catalog omits it', () {
      final Reciter old = Reciter.fromJson(<String, dynamic>{
        'id': 'legacy',
        'nameAr': '-',
        'nameEn': 'Legacy entry',
        'audioMode': 'per_ayah_files',
        'basePath': 'assets/audio/legacy',
        'availableSurahs': <int>[1],
      }, 'synthetic');

      expect(old.hasBismillah, isFalse);
      expect(old.hasIstiadhah, isFalse);
    });
  });

  group('bundled audio', () {
    // Per-ayah clip existence lives in assets_integrity_test.dart, which owns
    // it for every surah in the catalog. Duplicating it here would mean one
    // dropped file failing two suites with the same news.

    test(
      'each declared preamble is present, once, at reciter level',
      () async {
        for (final Reciter reciter in await source.getReciters()) {
          if (reciter.hasIstiadhah) {
            final ByteData data = await rootBundle.load(
              AssetPaths.istiadhahFile(reciter.basePath),
            );
            expect(data.lengthInBytes, greaterThan(0));
          }
          if (reciter.hasBismillah) {
            final ByteData data = await rootBundle.load(
              AssetPaths.bismillahFile(reciter.basePath),
            );
            expect(data.lengthInBytes, greaterThan(0));
          }
        }
      },
    );

    test('the silence spacer is bundled', () async {
      final ByteData data = await rootBundle.load(AssetPaths.silenceSpacer);
      expect(data.lengthInBytes, greaterThan(0));
    });
  });

  group('timings', () {
    test(
      'load and cover every ayah, with the istiadhah kept separate',
      () async {
        final Surah fatiha = await source.getSurah(1);
        final SurahTimings timings = await source.getTimings(
          reciterId: 'ahmed_khalil_shaheen',
          surahNumber: fatiha.number,
        );

        expect(timings.surahNumber, fatiha.number);
        expect(timings.ayahs, hasLength(fatiha.ayahCount));
        for (int ayah = 1; ayah <= fatiha.ayahCount; ayah++) {
          final AyahTiming? t = timings.timingFor(ayah);
          expect(t, isNotNull, reason: 'no timing for ayah $ayah');
          expect(t!.endMs, greaterThan(t.startMs));
        }

        // The recording opens with the isti'adhah. It is not ayah 1, and it must
        // never be reachable through the ayah map.
        expect(timings.istiadhah, isNotNull);
        expect(timings.istiadhah!.number, isNull);
        expect(
          timings.istiadhah!.endMs,
          lessThanOrEqualTo(timings.timingFor(1)!.startMs),
        );
      },
    );
  });

  group('MemorizationProgress', () {
    test('round-trips through its storage map', () {
      final MemorizationProgress progress = MemorizationProgress(
        surahNumber: 1,
        ayahNumber: 3,
        status: MemorizationStatus.inProgress,
        lastSessionAt: DateTime.utc(2026, 9, 7, 12, 30),
        cumulativeRepeats: 12,
      );

      expect(MemorizationProgress.fromMap(progress.toMap()), progress);
      expect(progress.storageKey, '1:3');
    });
  });
}
