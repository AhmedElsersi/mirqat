import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/error/failures.dart';
import 'package:mirqat/domain/engine/repetition_plan_builder.dart';
import 'package:mirqat/domain/entities/ayah_ref.dart';
import 'package:mirqat/domain/entities/playback_unit.dart';
import 'package:mirqat/domain/entities/plan_step.dart';
import 'package:mirqat/domain/entities/session_config.dart';
import 'package:mirqat/domain/entities/session_plan.dart';

const RepetitionPlanBuilder builder = RepetitionPlanBuilder();

/// The last three surahs, as the catalog counts them. Handed in like any
/// other count; the engine holds none of its own.
const Map<int, int> kCounts = <int, int>{112: 4, 113: 5, 114: 6};

SessionPlan plan(SessionConfig config, {Map<int, int> counts = kCounts}) =>
    builder
        .build(config, ayahCounts: counts)
        .fold(
          (Failure f) => fail('expected a plan, got: ${f.message}'),
          (SessionPlan p) => p,
        );

String failure(SessionConfig config, {Map<int, int> counts = kCounts}) =>
    builder
        .build(config, ayahCounts: counts)
        .fold(
          (Failure f) => f.message,
          (SessionPlan _) => fail('expected a failure, but a plan was built'),
        );

String describe(PlanStep step) => switch (step) {
  LearnStep() => 'LEARN ${step.fromRef} x${step.repeats}',
  ConnectStep() => 'CONNECT ${step.fromRef}-${step.toRef} x${step.repeats}',
};

void main() {
  group('a range that runs from one surah into the next', () {
    // 112:3 .. 113:2 — the last two ayahs of one surah, the first two of the
    // next.
    const SessionConfig config = SessionConfig(
      surahNumber: 112,
      startAyah: 3,
      endSurahNumber: 113,
      endAyah: 2,
      repeatCount: 2,
    );

    test('walks the mushaf in order, restarting the numbers at the surah', () {
      expect(RepetitionPlanBuilder.rangeOf(config, kCounts), const <AyahRef>[
        AyahRef(112, 3),
        AyahRef(112, 4),
        AyahRef(113, 1),
        AyahRef(113, 2),
      ]);
    });

    test('joining carries on across the boundary, back to where it began', () {
      expect(plan(config).steps.map(describe), <String>[
        'LEARN 112:3 x2',
        'LEARN 112:4 x2',
        'CONNECT 112:3-112:4 x2',
        'LEARN 113:1 x2',
        'CONNECT 112:3-113:1 x2',
        'LEARN 113:2 x2',
        'CONNECT 112:3-113:2 x2',
      ]);
    });

    test('every unit says which surah its ayah number belongs to', () {
      final SessionPlan p = plan(config);
      final PlanStep joined = p.steps[4];
      expect(joined.spansSurahs, isTrue);

      final List<PlaybackUnit> firstPass = p.units
          .where((PlaybackUnit u) => u.stepIndex == 4 && u.repeatIndex == 1)
          .toList();
      expect(firstPass.map((PlaybackUnit u) => u.ref), const <AyahRef>[
        AyahRef(112, 3),
        AyahRef(112, 4),
        AyahRef(113, 1),
      ]);
      expect(firstPass.first.blockFromRef, const AyahRef(112, 3));
      expect(firstPass.first.blockToRef, const AyahRef(113, 1));
      expect(firstPass.last.isLastUnitOfRepeat, isTrue);
    });

    test('the basmala is never one of the ayahs', () {
      // 113 opens with a standalone basmala. It is a preamble for the queue
      // to place; if it were ever a unit it would be drilled and joined like
      // an ayah, and the count of what was memorised would be wrong.
      final SessionPlan p = plan(config);
      expect(p.units.every((PlaybackUnit u) => u.ayahNumber >= 1), isTrue);
      expect(
        p.units
            .where((PlaybackUnit u) => u.surahNumber == 113)
            .map((PlaybackUnit u) => u.ayahNumber),
        everyElement(anyOf(1, 2)),
      );
    });

    test('continuous recites the whole range straight through', () {
      final SessionPlan p = plan(
        const SessionConfig(
          surahNumber: 112,
          startAyah: 3,
          endSurahNumber: 113,
          endAyah: 2,
          repeatCount: 2,
          connectMode: ConnectMode.continuous,
        ),
      );
      expect(p.steps.map(describe), <String>['CONNECT 112:3-113:2 x2']);
      expect(p.unitCount, 8);
    });

    test('no joining still learns every ayah, then closes over the range', () {
      final SessionPlan p = plan(
        const SessionConfig(
          surahNumber: 112,
          startAyah: 4,
          endSurahNumber: 113,
          endAyah: 1,
          repeatCount: 1,
          connectMode: ConnectMode.none,
        ),
      );
      expect(p.steps.map(describe), <String>[
        'LEARN 112:4 x1',
        'LEARN 113:1 x1',
        'CONNECT 112:4-113:1 x1',
      ]);
    });

    test('a surah wholly inside the range is recited whole', () {
      final List<AyahRef> range = RepetitionPlanBuilder.rangeOf(
        const SessionConfig(
          surahNumber: 112,
          startAyah: 4,
          endSurahNumber: 114,
          endAyah: 1,
        ),
        kCounts,
      );
      expect(range.first, const AyahRef(112, 4));
      expect(
        range.where((AyahRef r) => r.surah == 113).map((AyahRef r) => r.ayah),
        <int>[1, 2, 3, 4, 5],
      );
      expect(range.last, const AyahRef(114, 1));
      expect(
        plan(
          const SessionConfig(
            surahNumber: 112,
            startAyah: 4,
            endSurahNumber: 114,
            endAyah: 1,
          ),
        ).surahNumbers,
        <int>[112, 113, 114],
      );
    });

    test('an end ayah lower than the start is fine when the surah differs', () {
      // 112:4 .. 113:1 — "4 to 1" is inverted only inside a single surah.
      expect(
        builder
            .build(
              const SessionConfig(
                surahNumber: 112,
                startAyah: 4,
                endSurahNumber: 113,
                endAyah: 1,
              ),
              ayahCounts: kCounts,
            )
            .isRight(),
        isTrue,
      );
    });
  });

  group('what is refused', () {
    test('a range that runs backwards', () {
      expect(
        failure(
          const SessionConfig(
            surahNumber: 113,
            startAyah: 1,
            endSurahNumber: 112,
            endAyah: 4,
          ),
        ),
        contains('forward'),
      );
    });

    test('a surah in the range with no count from the catalog', () {
      expect(
        failure(
          const SessionConfig(
            surahNumber: 112,
            startAyah: 1,
            endSurahNumber: 114,
            endAyah: 2,
          ),
          counts: const <int, int>{112: 4, 114: 6},
        ),
        contains('surah 113'),
      );
    });

    test('an end ayah past the end of the last surah', () {
      expect(
        failure(
          const SessionConfig(
            surahNumber: 112,
            startAyah: 1,
            endSurahNumber: 113,
            endAyah: 6,
          ),
        ),
        contains('113'),
      );
    });

    test('a start ayah past the end of the first surah', () {
      expect(
        failure(
          const SessionConfig(
            surahNumber: 112,
            startAyah: 5,
            endSurahNumber: 113,
            endAyah: 1,
          ),
        ),
        contains('112'),
      );
    });
  });

  group('inside one surah nothing has changed', () {
    test('a config with no end surah ends in the surah it starts in', () {
      const SessionConfig c = SessionConfig(
        surahNumber: 1,
        startAyah: 1,
        endAyah: 3,
      );
      expect(c.endSurahNumber, 1);
      expect(c.spansSurahs, isFalse);
    });

    test('both ways of handing in the count build the same plan', () {
      const SessionConfig c = SessionConfig(
        surahNumber: 112,
        startAyah: 1,
        endAyah: 4,
      );
      expect(
        builder.buildOrThrow(c, surahAyahCount: 4),
        builder.buildOrThrow(c, ayahCounts: kCounts),
      );
    });

    test('moving the start to another surah takes the end with it', () {
      const SessionConfig c = SessionConfig(
        surahNumber: 112,
        startAyah: 1,
        endAyah: 4,
      );
      final SessionConfig moved = c.copyWith(
        surahNumber: 114,
        startAyah: 1,
        endAyah: 6,
      );
      expect(moved.endSurahNumber, 114);
    });
  });

  group('picking a changed plan up where the listener was', () {
    test('resumes at the first play of the ayah — the start of its drill', () {
      final SessionPlan p = plan(
        const SessionConfig(
          surahNumber: 112,
          startAyah: 3,
          endSurahNumber: 113,
          endAyah: 2,
          repeatCount: 2,
        ),
      );
      final int? at = p.firstUnitOf(const AyahRef(113, 1));
      expect(at, isNotNull);
      expect(p.units[at!].stepType, StepType.learn);
      expect(p.units[at].repeatIndex, 1);
      // Nothing before it has touched 113.
      expect(
        p.units.take(at).every((PlaybackUnit u) => u.surahNumber == 112),
        isTrue,
      );
    });

    test('an ayah the new range dropped has nowhere to resume', () {
      final SessionPlan p = plan(
        const SessionConfig(surahNumber: 113, startAyah: 1, endAyah: 2),
      );
      expect(p.firstUnitOf(const AyahRef(112, 4)), isNull);
    });
  });
}
