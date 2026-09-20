import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mirqat/data/models/ayah_timing.dart';
import 'package:mirqat/data/models/reciter.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:mirqat/domain/engine/repetition_plan_builder.dart';
import 'package:mirqat/domain/entities/playback_unit.dart';
import 'package:mirqat/domain/entities/plan_step.dart';
import 'package:mirqat/domain/entities/session_config.dart';
import 'package:mirqat/domain/entities/session_plan.dart';
import 'package:mirqat/services/audio/ayah_audio_resolver.dart';
import 'package:mirqat/services/audio/playback_queue.dart';

const Reciter perAyahReciter = Reciter(
  id: 'ahmed_khalil_shaheen',
  nameAr: 'أحمد خليل شاهين',
  nameEn: 'Ahmed Khalil Shaheen',
  audioMode: AudioMode.perAyahFiles,
  basePath: 'assets/audio/ahmed_khalil_shaheen',
  bundled: true,
  availableSurahs: <int>[1],
  hasIstiadhah: true,
  hasBismillah: true,
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
  hasBismillah: false,
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
        1,
        1,
        1,
        2,
        2,
        2,
        1,
        2,
        1,
        2,
        1,
        2,
        3,
        3,
        3,
        1,
        2,
        3,
        1,
        2,
        3,
        1,
        2,
        3,
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
      expect(queue.entries.whereType<SpacerQueueEntry>().length, expected);
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
      expect(queue.entries.whereType<AyahQueueEntry>().length, plan.unitCount);
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

  group('a session that runs on into the next surah', () {
    SessionPlan twoSurahs({ConnectMode mode = ConnectMode.cumulative}) =>
        const RepetitionPlanBuilder().buildOrThrow(
          SessionConfig(
            surahNumber: 112,
            startAyah: 4,
            endSurahNumber: 113,
            endAyah: 2,
            repeatCount: 3,
            connectMode: mode,
          ),
          ayahCounts: const <int, int>{112: 4, 113: 5},
        );

    List<int> basmalaIndices(PlaybackQueue queue) => <int>[
      for (int i = 0; i < queue.length; i++)
        if (queue.entries[i] case PreambleQueueEntry(
          kind: PreambleKind.bismillah,
          surah: 113,
        ))
          i,
    ];

    test('plays the new surah\'s basmala once, ahead of its first ayah', () {
      final PlaybackQueue queue = builder.build(
        plan: twoSurahs(),
        basmalaBeforeSurahs: const <int>{113},
      );

      final List<int> at = basmalaIndices(queue);
      expect(at, hasLength(1), reason: 'once, not once per repeat');

      // The next ayah play after it is the very first play of 113:1 …
      final int nextAyah = queue.entries.indexWhere(
        (QueueEntry e) => e is AyahQueueEntry,
        at.single,
      );
      final PlaybackUnit opening = queue.unitAt(nextAyah)!;
      expect(opening.surahNumber, 113);
      expect(opening.ayahNumber, 1);
      expect(opening.repeatIndex, 1);
      expect(opening.stepType, StepType.learn);

      // … and nothing of 113 was heard before it.
      expect(
        queue.entries
            .take(at.single)
            .whereType<AyahQueueEntry>()
            .every((AyahQueueEntry e) => e.unit.surahNumber == 112),
        isTrue,
      );
    });

    test('the basmala adds no recitation and is followed by a gap', () {
      final SessionPlan plan = twoSurahs();
      final PlaybackQueue queue = builder.build(
        plan: plan,
        basmalaBeforeSurahs: const <int>{113},
      );
      expect(queue.entries.whereType<AyahQueueEntry>().length, plan.unitCount);
      expect(
        queue.entries[basmalaIndices(queue).single + 1],
        const SpacerQueueEntry(GapKind.afterPreamble),
      );
    });

    test('recited straight through, it is still said once', () {
      final PlaybackQueue queue = builder.build(
        plan: twoSurahs(mode: ConnectMode.continuous),
        basmalaBeforeSurahs: const <int>{113},
      );
      expect(basmalaIndices(queue), hasLength(1));
    });

    test('a surah with no standalone basmala is entered without one', () {
      final PlaybackQueue queue = builder.build(plan: twoSurahs());
      expect(queue.entries.whereType<PreambleQueueEntry>(), isEmpty);
    });
  });

  group('resuming part-way', () {
    test('unit 0 starts at the top, preambles included', () {
      final PlaybackQueue queue = builder.build(
        plan: planFor(
          const SessionConfig(surahNumber: 1, startAyah: 1, endAyah: 2),
        ),
        includeIstiadhah: true,
      );
      expect(queue.indexOfUnit(0), 0);
      expect(queue.unitAt(0), isNull);
    });

    test('a later unit lands on exactly that ayah play', () {
      final SessionPlan plan = planFor(
        const SessionConfig(surahNumber: 1, startAyah: 1, endAyah: 3),
      );
      final PlaybackQueue queue = builder.build(
        plan: plan,
        includeIstiadhah: true,
      );
      for (final int unit in <int>[1, 5, plan.unitCount - 1]) {
        expect(queue.unitAt(queue.indexOfUnit(unit)), plan.units[unit]);
      }
      expect(() => queue.indexOfUnit(plan.unitCount), throwsRangeError);
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
      final Stream<int?> indices = Stream<int?>.fromIterable(<int?>[
        for (int i = 0; i < queue.length; i++) i,
      ]);

      final List<PlaybackUnit> seen = await queue
          .unitStreamFrom(indices)
          .toList();

      expect(seen.map((PlaybackUnit u) => u.ayahNumber), <int>[1, 2, 1, 2]);
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

  group('AyahAudioResolver — the bundled arm', () {
    test('per_ayah_files resolves to the zero-padded asset path', () {
      final AyahAudioResolver resolver = PerAyahFilesResolver();

      expect(
        uriOf(resolver.resolve(reciter: perAyahReciter, surah: 1, ayah: 7)),
        endsWith('assets/audio/ahmed_khalil_shaheen/001/007.mp3'),
      );
    });

    // The preambles and the spacer are not a layout decision and no longer
    // live on this class — see test/services/audio_resolver_test.dart.

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
