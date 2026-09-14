import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/error/failures.dart';
import 'package:mirqat/domain/engine/repetition_plan_builder.dart';
import 'package:mirqat/domain/entities/playback_unit.dart';
import 'package:mirqat/domain/entities/plan_step.dart';
import 'package:mirqat/domain/entities/session_config.dart';
import 'package:mirqat/domain/entities/session_plan.dart';

const RepetitionPlanBuilder builder = RepetitionPlanBuilder();

/// Al-Fatiha's real ayah count. Passed in from the catalog at every call site,
/// never read from a constant inside the engine.
const int kFatihaAyahCount = 7;

SessionPlan buildPlan(
  SessionConfig config, {
  int surahAyahCount = kFatihaAyahCount,
}) => builder
    .build(config, surahAyahCount: surahAyahCount)
    .fold(
      (Failure f) => fail('expected a plan, got a failure: ${f.message}'),
      (SessionPlan plan) => plan,
    );

String failureMessage(
  SessionConfig config, {
  int surahAyahCount = kFatihaAyahCount,
}) => builder
    .build(config, surahAyahCount: surahAyahCount)
    .fold(
      (Failure f) => f.message,
      (SessionPlan _) => fail('expected a failure, but a plan was built'),
    );

/// Compact rendering of a step, for readable expectations.
String describe(PlanStep step) => switch (step) {
  LearnStep(ayah: final int a) => 'LEARN $a x${step.repeats}',
  ConnectStep(from: final int f, to: final int t) =>
    'CONNECT $f-$t x${step.repeats}',
};

void main() {
  group('the worked example: surah 1, ayahs 1-3, N=3, cumulative', () {
    late SessionPlan plan;

    setUp(() {
      plan = buildPlan(
        const SessionConfig(surahNumber: 1, startAyah: 1, endAyah: 3),
      );
    });

    test('produces exactly the five steps from the spec', () {
      expect(plan.steps.map(describe), <String>[
        'LEARN 1 x3',
        'LEARN 2 x3',
        'CONNECT 1-2 x3',
        'LEARN 3 x3',
        'CONNECT 1-3 x3',
      ]);
    });

    test('emits no connect step after the first learn step', () {
      // Connecting a single ayah to nothing is a no-op.
      expect(plan.steps[1], isA<LearnStep>());
    });

    test('flattens to exactly 24 playback units', () {
      expect(plan.unitCount, 24);
    });

    test('plays the units in exactly the order the spec lists', () {
      expect(plan.units.map((PlaybackUnit u) => u.ayahNumber), <int>[
        1, 1, 1, // step 0: LEARN 1
        2, 2, 2, // step 1: LEARN 2
        1, 2, 1, 2, 1, 2, // step 2: CONNECT 1-2, three times through
        3, 3, 3, // step 3: LEARN 3
        1, 2, 3, 1, 2, 3, 1, 2, 3, // step 4: CONNECT 1-3, three times
      ]);
    });

    test('tags each unit with its step, repeat and block', () {
      final PlaybackUnit first = plan.units.first;
      expect(first.stepIndex, 0);
      expect(first.stepType, StepType.learn);
      expect(first.repeatIndex, 1);
      expect(first.totalRepeats, 3);
      expect(first.blockFrom, 1);
      expect(first.blockTo, 1);
      expect(first.isLastUnitOfRepeat, isTrue);
      expect(first.isLastUnitOfStep, isFalse);

      // CONNECT 1-2 starts at index 6 and alternates 1,2 three times over, so
      // index 9 is the ayah 2 that closes its second repetition.
      final PlaybackUnit mid = plan.units[9];
      expect(mid.stepIndex, 2);
      expect(mid.stepType, StepType.connect);
      expect(mid.ayahNumber, 2);
      expect(mid.repeatIndex, 2);
      expect(mid.blockFrom, 1);
      expect(mid.blockTo, 2);
      expect(mid.isLastUnitOfRepeat, isTrue);
      expect(mid.isLastUnitOfStep, isFalse);

      final PlaybackUnit last = plan.units.last;
      expect(last.stepIndex, 4);
      expect(last.ayahNumber, 3);
      expect(last.repeatIndex, 3);
      expect(last.isLastUnitOfRepeat, isTrue);
      expect(last.isLastUnitOfStep, isTrue);
    });

    test('marks exactly one last-unit-of-step per step', () {
      expect(
        plan.units.where((PlaybackUnit u) => u.isLastUnitOfStep).length,
        plan.stepCount,
      );
    });

    test('numbers repeats 1..N within every step', () {
      for (int stepIndex = 0; stepIndex < plan.stepCount; stepIndex++) {
        final List<PlaybackUnit> stepUnits = plan.units
            .where((PlaybackUnit u) => u.stepIndex == stepIndex)
            .toList();
        expect(stepUnits.first.repeatIndex, 1);
        expect(stepUnits.last.repeatIndex, 3);
        expect(
          stepUnits.every((PlaybackUnit u) => u.totalRepeats == 3),
          isTrue,
        );
      }
    });
  });

  group('cumulative invariants', () {
    /// N*M + N*sum(i for i in 2..M)
    int expectedUnits(int n, int m) {
      int connects = 0;
      for (int i = 2; i <= m; i++) {
        connects += i;
      }
      return n * m + n * connects;
    }

    test('holds across every range and repeat count in Al-Fatiha', () {
      for (int n = 1; n <= 20; n++) {
        for (int start = 1; start <= kFatihaAyahCount; start++) {
          for (int end = start; end <= kFatihaAyahCount; end++) {
            final SessionPlan plan = buildPlan(
              SessionConfig(
                surahNumber: 1,
                startAyah: start,
                endAyah: end,
                repeatCount: n,
              ),
            );
            final int m = end - start + 1;
            expect(
              plan.unitCount,
              expectedUnits(n, m),
              reason: 'range $start..$end, N=$n',
            );
            expect(plan.stepCount, m + (m - 1), reason: 'range $start..$end');
          }
        }
      }
    });

    test('full Al-Fatiha at N=3 is 13 steps and 102 units', () {
      final SessionPlan plan = buildPlan(
        const SessionConfig(surahNumber: 1, startAyah: 1, endAyah: 7),
      );

      expect(plan.stepCount, 13);
      expect(plan.unitCount, 102);
      expect(describe(plan.steps.last), 'CONNECT 1-7 x3');
    });

    test('a single-ayah range is one step and N units, with no connect', () {
      final SessionPlan plan = buildPlan(
        const SessionConfig(
          surahNumber: 1,
          startAyah: 4,
          endAyah: 4,
          repeatCount: 5,
        ),
      );

      expect(plan.stepCount, 1);
      expect(plan.steps.single, isA<LearnStep>());
      expect(plan.unitCount, 5);
      expect(plan.units.every((PlaybackUnit u) => u.ayahNumber == 4), isTrue);
    });

    test('N=1 gives one unit per ayah of each step', () {
      final SessionPlan plan = buildPlan(
        const SessionConfig(
          surahNumber: 1,
          startAyah: 1,
          endAyah: 3,
          repeatCount: 1,
        ),
      );

      expect(plan.steps.map(describe), <String>[
        'LEARN 1 x1',
        'LEARN 2 x1',
        'CONNECT 1-2 x1',
        'LEARN 3 x1',
        'CONNECT 1-3 x1',
      ]);
      expect(plan.units.map((PlaybackUnit u) => u.ayahNumber), <int>[
        1,
        2,
        1,
        2,
        3,
        1,
        2,
        3,
      ]);
      expect(plan.units.every((PlaybackUnit u) => u.repeatIndex == 1), isTrue);
      expect(
        plan.units.every(
          (PlaybackUnit u) => u.isLastUnitOfRepeat == u.isLastUnitOfStep,
        ),
        isTrue,
      );
    });

    test(
      'a range that does not start at ayah 1 connects from its own start',
      () {
        final SessionPlan plan = buildPlan(
          const SessionConfig(surahNumber: 1, startAyah: 5, endAyah: 7),
        );

        expect(plan.steps.map(describe), <String>[
          'LEARN 5 x3',
          'LEARN 6 x3',
          'CONNECT 5-6 x3',
          'LEARN 7 x3',
          'CONNECT 5-7 x3',
        ]);
      },
    );
  });

  group('continuous mode', () {
    test('the worked example: range 1-3 at 3 repeats is 1,2,3 x3', () {
      final SessionPlan plan = buildPlan(
        const SessionConfig(
          surahNumber: 1,
          startAyah: 1,
          endAyah: 3,
          repeatCount: 3,
          connectMode: ConnectMode.continuous,
        ),
      );

      // One step, nine recitations — asserted as the literal sequence rather
      // than as a count, because a count of nine is also what three separate
      // three-repeat learn steps would produce, and those are a different
      // session entirely.
      expect(plan.steps.map(describe), <String>['CONNECT 1-3 x3']);
      expect(
        plan.units.map((PlaybackUnit u) => u.ayahNumber).toList(),
        <int>[1, 2, 3, 1, 2, 3, 1, 2, 3],
      );
      expect(plan.unitCount, 9);
    });

    test('a single-ayah range is that ayah, repeatCount times', () {
      final SessionPlan plan = buildPlan(
        const SessionConfig(
          surahNumber: 1,
          startAyah: 4,
          endAyah: 4,
          repeatCount: 3,
          connectMode: ConnectMode.continuous,
        ),
      );

      expect(plan.steps.map(describe), <String>['CONNECT 4-4 x3']);
      expect(
        plan.units.map((PlaybackUnit u) => u.ayahNumber).toList(),
        <int>[4, 4, 4],
      );
    });

    test('a two-ayah range alternates', () {
      final SessionPlan plan = buildPlan(
        const SessionConfig(
          surahNumber: 1,
          startAyah: 2,
          endAyah: 3,
          repeatCount: 3,
          connectMode: ConnectMode.continuous,
        ),
      );

      expect(
        plan.units.map((PlaybackUnit u) => u.ayahNumber).toList(),
        <int>[2, 3, 2, 3, 2, 3],
      );
    });

    test('repeatCount 1 is a single pass', () {
      final SessionPlan plan = buildPlan(
        const SessionConfig(
          surahNumber: 1,
          startAyah: 1,
          endAyah: 3,
          repeatCount: 1,
          connectMode: ConnectMode.continuous,
        ),
      );

      expect(plan.steps.map(describe), <String>['CONNECT 1-3 x1']);
      expect(
        plan.units.map((PlaybackUnit u) => u.ayahNumber).toList(),
        <int>[1, 2, 3],
      );
    });

    test('emits no per-ayah learn steps at all', () {
      final SessionPlan plan = buildPlan(
        const SessionConfig(
          surahNumber: 1,
          startAyah: 1,
          endAyah: 7,
          connectMode: ConnectMode.continuous,
        ),
      );

      expect(plan.steps.whereType<LearnStep>(), isEmpty);
    });

    test('defaults finalFullPass to false', () {
      // The single step already spans the range, so a closing pass would just
      // recite it again — and would break the worked example above.
      expect(
        const SessionConfig(
          surahNumber: 1,
          startAyah: 1,
          endAyah: 3,
          connectMode: ConnectMode.continuous,
        ).finalFullPass,
        isFalse,
      );
    });

    test('honours finalFullPass when it is switched on explicitly', () {
      final SessionPlan plan = buildPlan(
        const SessionConfig(
          surahNumber: 1,
          startAyah: 1,
          endAyah: 3,
          repeatCount: 2,
          connectMode: ConnectMode.continuous,
          finalFullPass: true,
        ),
      );

      expect(plan.steps.map(describe), <String>[
        'CONNECT 1-3 x2',
        'CONNECT 1-3 x2',
      ]);
    });

    test('gaps: ayahs inside a pass, the longer repeat gap between passes', () {
      final SessionPlan plan = buildPlan(
        const SessionConfig(
          surahNumber: 1,
          startAyah: 1,
          endAyah: 3,
          repeatCount: 2,
          connectMode: ConnectMode.continuous,
          intraBlockPauseMs: 300,
          betweenRepeatPauseMs: 900,
        ),
      );

      // The project already had a between-repetitions pause, so continuous
      // reuses it for the gap between passes rather than inventing pause x 2.
      final List<int> gaps = <int>[
        for (int i = 0; i < plan.units.length - 1; i++)
          plan.gapAfter(plan.units[i]).inMilliseconds,
      ];
      expect(gaps, <int>[300, 300, 900, 300, 300]);
    });
  });

  group('none mode', () {
    test('emits learn steps only, then the closing full pass', () {
      final SessionPlan plan = buildPlan(
        const SessionConfig(
          surahNumber: 1,
          startAyah: 1,
          endAyah: 3,
          connectMode: ConnectMode.none,
        ),
      );

      expect(plan.steps.map(describe), <String>[
        'LEARN 1 x3',
        'LEARN 2 x3',
        'LEARN 3 x3',
        'CONNECT 1-3 x3',
      ]);
    });

    test(
      'emits nothing but learn steps when the full pass is switched off',
      () {
        final SessionPlan plan = buildPlan(
          const SessionConfig(
            surahNumber: 1,
            startAyah: 1,
            endAyah: 3,
            connectMode: ConnectMode.none,
            finalFullPass: false,
          ),
        );

        expect(plan.steps.every((PlanStep s) => s is LearnStep), isTrue);
        expect(plan.unitCount, 9);
      },
    );
  });

  group('cumulative with finalFullPass switched on', () {
    test('appends one more pass over the whole range', () {
      final SessionPlan plan = buildPlan(
        const SessionConfig(
          surahNumber: 1,
          startAyah: 1,
          endAyah: 3,
          finalFullPass: true,
        ),
      );

      // The cumulative mode's last connect step already spans the range, so
      // this is a deliberate extra reinforcement round, not a duplicate bug.
      expect(plan.steps.map(describe), <String>[
        'LEARN 1 x3',
        'LEARN 2 x3',
        'CONNECT 1-2 x3',
        'LEARN 3 x3',
        'CONNECT 1-3 x3',
        'CONNECT 1-3 x3',
      ]);
      expect(plan.unitCount, 24 + 9);
    });
  });

  group('validation', () {
    test('rejects an inverted range', () {
      expect(
        failureMessage(
          const SessionConfig(surahNumber: 1, startAyah: 5, endAyah: 2),
        ),
        allOf(contains('inverted'), contains('startAyah 5')),
      );
    });

    test('rejects a repeat count of zero', () {
      expect(
        failureMessage(
          const SessionConfig(
            surahNumber: 1,
            startAyah: 1,
            endAyah: 3,
            repeatCount: 0,
          ),
        ),
        contains('repeatCount must be between 1 and 999'),
      );
    });

    test('rejects a repeat count above the maximum', () {
      expect(
        failureMessage(
          const SessionConfig(
            surahNumber: 1,
            startAyah: 1,
            endAyah: 3,
            repeatCount: 1000,
          ),
        ),
        contains('got 1000'),
      );
    });

    test('rejects an end ayah beyond the surah', () {
      expect(
        failureMessage(
          const SessionConfig(surahNumber: 1, startAyah: 1, endAyah: 8),
        ),
        allOf(contains('1..8'), contains('which has 7 ayahs')),
      );
    });

    test('rejects a start ayah below 1', () {
      expect(
        failureMessage(
          const SessionConfig(surahNumber: 1, startAyah: 0, endAyah: 3),
        ),
        contains('startAyah must be at least 1'),
      );
    });

    test('validates against the catalog count, not a constant', () {
      // The same range is fine in a 286-ayah surah and out of bounds in a
      // 3-ayah one.
      const SessionConfig config = SessionConfig(
        surahNumber: 2,
        startAyah: 10,
        endAyah: 20,
      );

      expect(builder.build(config, surahAyahCount: 286).isRight(), isTrue);
      expect(
        failureMessage(config, surahAyahCount: 3),
        contains('which has 3 ayahs'),
      );
    });

    test('rejects a playback speed outside the allowed band', () {
      expect(
        failureMessage(
          const SessionConfig(
            surahNumber: 1,
            startAyah: 1,
            endAyah: 3,
            playbackSpeed: 2.0,
          ),
        ),
        contains('playbackSpeed must be between 0.5 and 1.5'),
      );
    });

    test('rejects a negative pause', () {
      expect(
        failureMessage(
          const SessionConfig(
            surahNumber: 1,
            startAyah: 1,
            endAyah: 3,
            intraBlockPauseMs: -1,
          ),
        ),
        contains('must not be negative'),
      );
    });

    test('buildOrThrow throws on an invalid config', () {
      expect(
        () => builder.buildOrThrow(
          const SessionConfig(surahNumber: 1, startAyah: 3, endAyah: 1),
          surahAyahCount: kFatihaAyahCount,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('duration estimate', () {
    // Real clip lengths for Ahmed Khalil Shaheen's Al-Fatiha.
    const Map<int, Duration> clips = <int, Duration>{
      1: Duration(milliseconds: 3527),
      2: Duration(milliseconds: 3918),
      3: Duration(milliseconds: 2795),
    };

    test('sums real clip lengths and the gaps between them', () {
      final SessionPlan plan = buildPlan(
        const SessionConfig(surahNumber: 1, startAyah: 1, endAyah: 3),
      );

      // 24 units: ayah 1 nine times, ayah 2 nine times, ayah 3 six times.
      const int audioMs = 9 * 3527 + 9 * 3918 + 6 * 2795;
      // 23 gaps: one after every unit but the last. Four steps end mid-plan,
      // and each step has N-1 internal repeat boundaries.
      const int stepGaps = 4 * 1500;
      const int repeatGaps = 5 * 2 * 800;
      const int intraGaps = 23 - 4 - 10;

      expect(
        plan.estimatedDuration(ayahDurations: clips),
        Duration(
          milliseconds: audioMs + stepGaps + repeatGaps + intraGaps * 300,
        ),
      );
    });

    test('scales with playback speed', () {
      final SessionPlan normal = buildPlan(
        const SessionConfig(surahNumber: 1, startAyah: 1, endAyah: 3),
      );
      final SessionPlan fast = buildPlan(
        const SessionConfig(
          surahNumber: 1,
          startAyah: 1,
          endAyah: 3,
          playbackSpeed: 1.5,
        ),
      );

      expect(
        fast.estimatedDuration(ayahDurations: clips).inMilliseconds,
        closeTo(
          normal.estimatedDuration(ayahDurations: clips).inMilliseconds / 1.5,
          1,
        ),
      );
    });

    test('refuses to guess when a clip duration is missing', () {
      final SessionPlan plan = buildPlan(
        const SessionConfig(surahNumber: 1, startAyah: 1, endAyah: 3),
      );

      expect(
        () => plan.estimatedDuration(
          ayahDurations: const <int, Duration>{1: Duration(seconds: 3)},
        ),
        throwsArgumentError,
      );
    });
  });

  group('firstUnitOfStep', () {
    test('points at the first unit of each step', () {
      final SessionPlan plan = buildPlan(
        const SessionConfig(surahNumber: 1, startAyah: 1, endAyah: 3),
      );

      expect(plan.firstUnitOfStep(0), 0);
      expect(plan.firstUnitOfStep(1), 3);
      expect(plan.firstUnitOfStep(2), 6);
      expect(plan.firstUnitOfStep(3), 12);
      expect(plan.firstUnitOfStep(4), 15);
    });
  });
}
