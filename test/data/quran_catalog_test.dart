import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahfiz/core/constants/asset_paths.dart';
import 'package:tahfiz/data/datasources/asset_reader.dart';
import 'package:tahfiz/data/datasources/quran_local_data_source.dart';
import 'package:tahfiz/data/models/ayah.dart';
import 'package:tahfiz/data/models/ayah_timing.dart';
import 'package:tahfiz/data/models/memorization_progress.dart';
import 'package:tahfiz/data/models/reciter.dart';
import 'package:tahfiz/data/models/surah.dart';
import 'package:tahfiz/core/extensions/arabic_text_extensions.dart';

/// Exercises the loaders against the assets that actually ship, so a file that
/// is missing, undeclared in pubspec.yaml, or out of step with the catalog
/// fails here rather than at playback time.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late QuranLocalDataSource source;

  setUp(() => source = QuranLocalDataSourceImpl(BundleAssetReader()));

  group('surah catalog', () {
    test('loads and matches the shipped data contract', () async {
      final List<Surah> surahs = await source.getSurahs();

      expect(surahs, hasLength(1));
      final Surah fatiha = surahs.single;
      expect(fatiha.number, 1);
      expect(fatiha.nameAr, 'الفاتحة');
      expect(fatiha.nameEn, 'Al-Fatiha');
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
      await expectLater(source.getSurah(2), throwsA(isA<Exception>()));
    });
  });

  group('ayah text', () {
    test('loads exactly the ayahs the catalog declares', () async {
      final Surah fatiha = await source.getSurah(1);
      final List<Ayah> ayahs = await source.getAyahs(1);

      expect(ayahs, hasLength(fatiha.ayahCount));
      expect(
        ayahs.map((Ayah a) => a.number),
        List<int>.generate(fatiha.ayahCount, (int i) => i + 1),
      );
      for (final Ayah ayah in ayahs) {
        expect(ayah.surahNumber, 1);
        expect(ayah.text.trim(), isNotEmpty);
      }
    });

    test('is NFC-normalised, so equal ayahs compare equal', () async {
      for (final Ayah ayah in await source.getAyahs(1)) {
        expect(
          ayah.text.isArabicNfc,
          isTrue,
          reason: 'ayah ${ayah.number} is not in NFC after loading',
        );
      }
    });
  });

  group('reciter catalog', () {
    test('loads the bundled reciter', () async {
      final List<Reciter> reciters = await source.getReciters();

      expect(reciters, hasLength(1));
      final Reciter reciter = reciters.single;
      expect(reciter.id, 'ahmed_khalil_shaheen');
      expect(reciter.nameAr, 'أحمد خليل شاهين');
      expect(reciter.audioMode, AudioMode.perAyahFiles);
      expect(reciter.bundled, isTrue);
      expect(reciter.hasIstiadhah, isTrue);
      expect(reciter.hasSurah(1), isTrue);
      expect(reciter.hasSurah(2), isFalse);
    });
  });

  group('bundled audio', () {
    test('every ayah the catalog declares has a clip in the bundle', () async {
      final Reciter reciter = await source.getReciter('ahmed_khalil_shaheen');
      final Surah fatiha = await source.getSurah(1);

      for (int ayah = 1; ayah <= fatiha.ayahCount; ayah++) {
        final String path = AssetPaths.perAyahFile(reciter.basePath, 1, ayah);
        final ByteData data = await rootBundle.load(path);
        expect(data.lengthInBytes, greaterThan(0), reason: '$path is empty');
      }
    });

    test(
      'the istiadhah clip is present when the reciter declares one',
      () async {
        final Reciter reciter = await source.getReciter('ahmed_khalil_shaheen');
        expect(reciter.hasIstiadhah, isTrue);

        final ByteData data = await rootBundle.load(
          AssetPaths.istiadhahFile(reciter.basePath, 1),
        );
        expect(data.lengthInBytes, greaterThan(0));
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
        final SurahTimings timings = await source.getTimings(
          reciterId: 'ahmed_khalil_shaheen',
          surahNumber: 1,
        );

        expect(timings.surahNumber, 1);
        expect(timings.ayahs, hasLength(7));
        for (int ayah = 1; ayah <= 7; ayah++) {
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
