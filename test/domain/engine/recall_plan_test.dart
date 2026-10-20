import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/error/failures.dart';
import 'package:mirqat/domain/engine/repetition_plan_builder.dart';
import 'package:mirqat/domain/entities/ayah_ref.dart';
import 'package:mirqat/domain/entities/plan_step.dart';
import 'package:mirqat/domain/entities/recall_gap.dart';
import 'package:mirqat/domain/entities/session_config.dart';
import 'package:mirqat/domain/entities/session_plan.dart';

const RepetitionPlanBuilder builder = RepetitionPlanBuilder();

SessionPlan planFor(SessionConfig config) => builder
    .build(config, surahAyahCount: 7)
    .fold(
      (Failure f) => fail('expected a plan, got: ${f.message}'),
      (SessionPlan p) => p,
    );

String describe(PlanStep step) => switch (step) {
  LearnStep(ayah: final int a) => 'LEARN $a x${step.repeats}',
  RecallStep(ayah: final int a) => 'RECALL $a x${step.repeats}',
  ConnectStep(from: final int f, to: final int t) =>
    'CONNECT $f-$t x${step.repeats}',
};

void main() {
  group('recall steps in the plan', () {
    test('each learn step is followed by its recall step, before the join', () {
      final SessionPlan plan = planFor(
        const SessionConfig(
          surahNumber: 1,
          startAyah: 1,
          endAyah: 3,
          repeatCount: 3,
          recallRounds: 2,
        ),
      );
      expect(plan.steps.map(describe), <String>[
        'LEARN 1 x3',
        'RECALL 1 x2',
        'LEARN 2 x3',
        'RECALL 2 x2',
        'CONNECT 1-2 x3',
        'LEARN 3 x3',
        'RECALL 3 x2',
        'CONNECT 1-3 x3',
      ]);
    });

    test('zero rounds — the default — adds nothing', () {
      final SessionPlan plan = planFor(
        const SessionConfig(surahNumber: 1, startAyah: 1, endAyah: 3),
      );
      expect(plan.steps.whereType<RecallStep>(), isEmpty);
    });

    test('continuous mode ignores recall rounds rather than refusing them', () {
      final SessionPlan plan = planFor(
        const SessionConfig(
          surahNumber: 1,
          startAyah: 1,
          endAyah: 3,
          connectMode: ConnectMode.continuous,
          recallRounds: 3,
        ),
      );
      expect(plan.steps.whereType<RecallStep>(), isEmpty);
    });

    test('a recall unit flattens as a play of its ayah, typed recall', () {
      final SessionPlan plan = planFor(
        const SessionConfig(
          surahNumber: 1,
          startAyah: 2,
          endAyah: 2,
          repeatCount: 2,
          recallRounds: 2,
        ),
      );
      // LEARN 2 x2 then RECALL 2 x2: four units, the last two recall plays.
      expect(plan.unitCount, 4);
      expect(
        plan.units.map((u) => '${u.stepType.name} ${u.ayahNumber}'),
        <String>['learn 2', 'learn 2', 'recall 2', 'recall 2'],
      );
    });

    test('rounds outside the bounds are refused with a reason', () {
      final String message = builder
          .build(
            const SessionConfig(
              surahNumber: 1,
              startAyah: 1,
              endAyah: 1,
              recallRounds: SessionConfig.maxRecallRounds + 1,
            ),
            surahAyahCount: 7,
          )
          .fold(
            (Failure f) => f.message,
            (_) => fail('expected a failure, but a plan was built'),
          );
      expect(message, contains('recallRounds'));
    });
  });

  group('the recall gap', () {
    test('is the clip and a fifth again, plus the breath', () {
      expect(
        RecallGap.of(const Duration(seconds: 5)),
        const Duration(seconds: 6, milliseconds: 600),
      );
    });

    test('falls back to a fixed gap for an unmeasured clip', () {
      expect(RecallGap.of(null), RecallGap.fallback);
    });

    test('is counted into the estimated duration, once per recall play', () {
      const SessionConfig withRecall = SessionConfig(
        surahNumber: 1,
        startAyah: 1,
        endAyah: 1,
        repeatCount: 1,
        recallRounds: 1,
      );
      const SessionConfig without = SessionConfig(
        surahNumber: 1,
        startAyah: 1,
        endAyah: 1,
        repeatCount: 1,
      );
      final Map<AyahRef, Duration> clips = <AyahRef, Duration>{
        const AyahRef(1, 1): const Duration(seconds: 5),
      };
      final Duration a = planFor(
        withRecall,
      ).estimatedDuration(clipDurations: clips);
      final Duration b = planFor(
        without,
      ).estimatedDuration(clipDurations: clips);
      // One more play of the ayah, plus its recall gap.
      expect(
        a - b,
        const Duration(seconds: 5) + RecallGap.of(const Duration(seconds: 5)),
      );
    });
  });
}
