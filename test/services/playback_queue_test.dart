import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:tahfiz/core/constants/asset_paths.dart';
import 'package:tahfiz/data/models/ayah_timing.dart';
import 'package:tahfiz/data/models/reciter.dart';
import 'package:tahfiz/data/models/surah.dart';
import 'package:tahfiz/domain/engine/repetition_plan_builder.dart';
import 'package:tahfiz/domain/entities/playback_unit.dart';
import 'package:tahfiz/domain/entities/session_config.dart';
import 'package:tahfiz/domain/entities/session_plan.dart';
import 'package:tahfiz/services/audio/ayah_audio_resolver.dart';
import 'package:tahfiz/services/audio/playback_queue.dart';

const Reciter perAyahReciter = Reciter(
  id: 'ahmed_khalil_shaheen',
  nameAr: 'أحمد خليل شاهين',
  nameEn: 'Ahmed Khalil Shaheen',
  audioMode: AudioMode.perAyahFiles,
  basePath: 'assets/audio/ahmed_khalil_shaheen',
  bundled: true,
  availableSurahs: <int>[1],
  hasIstiadhah: true,
);

const Reciter timingsReciter = Reciter(
  id: 'other',
  nameAr: 'ق',
  nameEn: 'Other',
  audioMode: AudioMode.singleFileWithTimings,
  basePath: 'assets/audio/other',
  bundled: true,
  availableSurahs: <int>[1],
  hasIstiadhah: false,
);

const Surah fatiha = Surah(
  number: 1,
  nameAr: 'الفاتحة',
  nameEn: 'Al-Fatiha',
  ayahCount: 7,
  revelationPlace: RevelationPlace.makkah,
  bismillahMode: BismillahMode.countedAsAyah1,
);

const Surah baqarah = Surah(
  number: 2,
  nameAr: 'البقرة',
  nameEn: 'Al-Baqarah',
  ayahCount: 286,
  revelationPlace: RevelationPlace.madinah,
  bismillahMode: BismillahMode.separatePreamble,
);

SessionPlan planFor(SessionConfig config, {int ayahCount = 7}) =>
    const RepetitionPlanBuilder()
        .build(config, surahAyahCount: ayahCount)
        .fold((_) => throw StateError('bad config'), (SessionPlan p) => p);

String uriOf(AudioSource source) => (source as UriAudioSource).uri.toString();

void main() {
  const PlaybackQueueBuilder builder = PlaybackQueueBuilder();

  group('gap quantisation', () {
    test('rounds each gap to the nearest whole spacer clip', () {
      // The shipped spacer is 400 ms, so the configured 300/800/1500 defaults
      // are realised as 400/800/1600.
      expect(builder.spacerCount(300), 1);
      expect(builder.spacerCount(800), 2);
      expect(builder.spacerCount(1500), 4);
      expect(builder.spacerCount(0), 0);
      expect(builder.spacerCount(150), 0);
      expect(builder.spacerCount(200), 1);
    });
  });

  group('the worked example queue: ayahs 1-3, N=3, cumulative', () {
    late SessionPlan plan;
    late PlaybackQueue queue;

    setUp(() {
      plan = planFor(
        const SessionConfig(surahNumber: 1, startAyah: 1, endAyah: 3),
      );
      queue = builder.build(plan: plan);
    });

    test('plays the ayahs in exactly the order the spec lists', () {
      final List<int> recited = <int>[
        for (final QueueEntry e in queue.entries)
          if (e is AyahQueueEntry) e.unit.ayahNumber,
      ];

      expect(recited, <int>[
        1, 1, 1,
        2, 2, 2,
        1, 2, 1, 2, 1, 2,
        3, 3, 3,
        1, 2, 3, 1, 2, 3, 1, 2, 3,
      ]);
      expect(recited, hasLength(24));
    });

    test('separates every ayah play with silence', () {
      for (int i = 0; i < queue.length - 1; i++) {
        if (queue.entries[i] is! AyahQueueEntry) continue;
        expect(
          queue.entries[i + 1],
          isA<SpacerQueueEntry>(),
          reason: 'no gap after queue index $i',
        );
      }
    });

    test('uses the right gap kind at each boundary', () {
      // Inside CONNECT 1-2: ayah 1 -> ayah 2 is intra-block, ayah 2 -> the
      // next repetition is a repeat boundary.
      final int stepStart = queue.indexOfStep(2);
      expect(
        (queue.entries[stepStart + 1] as SpacerQueueEntry).kind,
        GapKind.intraBlock,
      );
      final int afterFirstRepeat = stepStart + 1 + 1 + 1;
      expect(
        (queue.entries[afterFirstRepeat] as SpacerQueueEntry).kind,
        GapKind.betweenRepeats,
      );
    });

    test('holds the right number of spacers', () {
      // 23 boundaries: 4 between steps (4 clips each), 10 between repeats
      // (2 each), 9 intra-block (1 each).
      const int expected = 4 * 4 + 10 * 2 + 9 * 1;
      expect(
        queue.entries.whereType<SpacerQueueEntry>().length,
        expected,
      );
      expect(queue.length, 24 + expected);
    });

    test('ends on an ayah, never on silence', () {
      expect(queue.entries.last, isA<AyahQueueEntry>());
    });

    test('indexOfStep lands on the first ayah play of each step', () {
      for (int step = 0; step < plan.stepCount; step++) {
        final int index = queue.indexOfStep(step);
        final QueueEntry entry = queue.entries[index];
        expect(entry, isA<AyahQueueEntry>());
        final PlaybackUnit unit = (entry as AyahQueueEntry).unit;
        expect(unit.stepIndex, step);
        expect(unit.repeatIndex, 1);
        expect(unit.ayahNumber, plan.steps[step].fromAyah);
      }
    });
  });

  group('preambles', () {
    test('the istiadhah leads the queue but is not a recitation', () {
      final SessionPlan plan = planFor(
        const SessionConfig(
          surahNumber: 1,
          startAyah: 1,
          endAyah: 2,
          playIstiadhah: true,
        ),
      );
      final PlaybackQueue queue = builder.build(
        plan: plan,
        includeIstiadhah: true,
      );

      expect(
        queue.entries.first,
        const PreambleQueueEntry(PreambleKind.istiadhah),
      );
      expect(queue.unitAt(0), isNull);
      // The recitation count is untouched by the preamble.
      expect(
        queue.entries.whereType<AyahQueueEntry>().length,
        plan.unitCount,
      );
    });

    test('a separate_preamble surah gets a bismillah clip', () {
      final SessionPlan plan = planFor(
        const SessionConfig(surahNumber: 2, startAyah: 1, endAyah: 2),
        ayahCount: 286,
      );
      final PlaybackQueue queue = builder.build(
        plan: plan,
        includeBismillah: true,
      );

      expect(
        queue.entries.first,
        const PreambleQueueEntry(PreambleKind.bismillah),
      );
    });
  });

  group('unitStreamFrom', () {
    test('reports each ayah once and ignores the gaps between them', () async {
      final SessionPlan plan = planFor(
        const SessionConfig(
          surahNumber: 1,
          startAyah: 1,
          endAyah: 2,
          repeatCount: 1,
        ),
      );
      final PlaybackQueue queue = builder.build(plan: plan);

      // Walk the whole queue the way the player would.
      final Stream<int?> indices = Stream<int?>.fromIterable(
        <int?>[for (int i = 0; i < queue.length; i++) i],
      );

      final List<PlaybackUnit> seen = await queue
          .unitStreamFrom(indices)
          .toList();

      expect(
        seen.map((PlaybackUnit u) => u.ayahNumber),
        <int>[1, 2, 1, 2],
      );
    });

    test('a null index emits nothing', () async {
      final SessionPlan plan = planFor(
        const SessionConfig(surahNumber: 1, startAyah: 1, endAyah: 1),
      );
      final PlaybackQueue queue = builder.build(plan: plan);

      expect(
        await queue.unitStreamFrom(Stream<int?>.value(null)).toList(),
        isEmpty,
      );
    });
  });

  group('AyahAudioResolver', () {
    test('per_ayah_files resolves to the zero-padded asset path', () {
      final AyahAudioResolver resolver = PerAyahFilesResolver();

      expect(
        uriOf(resolver.resolve(reciter: perAyahReciter, surah: 1, ayah: 7)),
        endsWith('assets/audio/ahmed_khalil_shaheen/001/007.mp3'),
      );
    });

    test('per_ayah_files resolves the istiadhah only when declared', () {
      final AyahAudioResolver resolver = PerAyahFilesResolver();

      expect(
        uriOf(
          resolver.resolveIstiadhah(reciter: perAyahReciter, surah: 1)!,
        ),
        endsWith('assets/audio/ahmed_khalil_shaheen/001/istiadhah.mp3'),
      );
      expect(
        resolver.resolveIstiadhah(reciter: timingsReciter, surah: 1),
        isNull,
      );
    });

    test('bismillah is offered only for separate_preamble surahs', () {
      final AyahAudioResolver resolver = PerAyahFilesResolver();

      expect(
        resolver.resolveBismillah(reciter: perAyahReciter, surah: fatiha),
        isNull,
      );
      expect(
        uriOf(
          resolver.resolveBismillah(
            reciter: perAyahReciter,
            surah: baqarah,
          )!,
        ),
        endsWith('assets/audio/ahmed_khalil_shaheen/bismillah.mp3'),
      );
    });

    test('the spacer resolves to the sample-exact WAV', () {
      expect(
        uriOf(PerAyahFilesResolver().resolveSpacer()),
        endsWith(AssetPaths.silenceSpacer),
      );
    });

    test('single_file_with_timings clips one file per ayah', () {
      final AyahAudioResolver resolver = TimingsAudioResolver(
        const SurahTimings(
          surahNumber: 1,
          istiadhah: AyahTiming(number: null, startMs: 480, endMs: 4380),
          ayahs: <int, AyahTiming>{
            1: AyahTiming(number: 1, startMs: 5480, endMs: 8980),
            2: AyahTiming(number: 2, startMs: 9920, endMs: 13790),
          },
        ),
      );

      final ClippingAudioSource source =
          resolver.resolve(reciter: timingsReciter, surah: 1, ayah: 2)
              as ClippingAudioSource;

      expect(uriOf(source.child), endsWith('assets/audio/other/001.mp3'));
      expect(source.start, const Duration(milliseconds: 9920));
      expect(source.end, const Duration(milliseconds: 13790));
    });

    test('single_file_with_timings refuses an ayah it has no window for', () {
      final AyahAudioResolver resolver = TimingsAudioResolver(
        const SurahTimings(
          surahNumber: 1,
          istiadhah: null,
          ayahs: <int, AyahTiming>{
            1: AyahTiming(number: 1, startMs: 0, endMs: 100),
          },
        ),
      );

      expect(
        () => resolver.resolve(reciter: timingsReciter, surah: 1, ayah: 5),
        throwsA(isA<Exception>()),
      );
    });
  });
}
