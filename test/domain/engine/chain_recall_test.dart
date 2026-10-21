import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/error/failures.dart';
import 'package:mirqat/domain/engine/repetition_plan_builder.dart';
import 'package:mirqat/domain/entities/ayah_ref.dart';
import 'package:mirqat/domain/entities/plan_step.dart';
import 'package:mirqat/domain/entities/playback_unit.dart';
import 'package:mirqat/domain/entities/recall_gap.dart';
import 'package:mirqat/domain/entities/session_config.dart';
import 'package:mirqat/domain/entities/session_plan.dart';
import 'package:mirqat/services/audio/playback_queue.dart';

const RepetitionPlanBuilder builder = RepetitionPlanBuilder();

SessionPlan planFor(SessionConfig config, {Map<int, int>? counts}) => builder
    .build(config, ayahCounts: counts ?? const <int, int>{1: 7})
    .fold(
      (Failure f) => fail('expected a plan, got: ${f.message}'),
      (SessionPlan p) => p,
    );

String describe(PlanStep step) => switch (step) {
  LearnStep(ayah: final int a) => 'LEARN $a',
  RecallStep(ayah: final int a) => 'RECALL $a',
  ConnectStep(from: final int f, to: final int t) => 'CONNECT $f-$t',
  ChainStep(:final AyahRef cue, :final AyahRef next) => 'CHAIN $cue>$next',
};

void main() {
  group('the chaining drill — what comes next?', () {
    test('closes the drill with one link per consecutive pair', () {
      final SessionPlan plan = planFor(
        const SessionConfig(
          surahNumber: 1,
          startAyah: 1,
          endAyah: 3,
          repeatCount: 1,
          chainRecall: true,
        ),
      );
      expect(plan.steps.map(describe), <String>[
        'LEARN 1',
        'LEARN 2',
        'CONNECT 1-2',
        'LEARN 3',
        'CONNECT 1-3',
        'CHAIN 1:1>1:2',
        'CHAIN 1:2>1:3',
      ]);
    });

    test('suits continuous mode too: it is a pass, not a drill step', () {
      final SessionPlan plan = planFor(
        const SessionConfig(
          surahNumber: 1,
          startAyah: 4,
          endAyah: 5,
          connectMode: ConnectMode.continuous,
          repeatCount: 2,
          chainRecall: true,
        ),
      );
      expect(plan.steps.whereType<ChainStep>().length, 1);
      expect(plan.steps.last, isA<ChainStep>());
    });

    test('a range of one ayah has no link and adds nothing', () {
      final SessionPlan plan = planFor(
        const SessionConfig(
          surahNumber: 1,
          startAyah: 2,
          endAyah: 2,
          chainRecall: true,
        ),
      );
      expect(plan.steps.whereType<ChainStep>(), isEmpty);
    });

    test('a range into the next surah tests the link across the boundary', () {
      final SessionPlan plan = planFor(
        const SessionConfig(
          surahNumber: 112,
          startAyah: 4,
          endSurahNumber: 113,
          endAyah: 1,
          repeatCount: 1,
          connectMode: ConnectMode.none,
          finalFullPass: false,
          chainRecall: true,
        ),
        counts: const <int, int>{112: 4, 113: 5},
      );
      expect(plan.steps.whereType<ChainStep>().map(describe), <String>[
        'CHAIN 112:4>113:1',
      ]);
    });

    test('off by default', () {
      final SessionPlan plan = planFor(
        const SessionConfig(surahNumber: 1, startAyah: 1, endAyah: 3),
      );
      expect(plan.steps.whereType<ChainStep>(), isEmpty);
    });
  });

  group('asked plays', () {
    test('the cue plays plainly; only the ayah after it is asked', () {
      final SessionPlan plan = planFor(
        const SessionConfig(
          surahNumber: 1,
          startAyah: 1,
          endAyah: 2,
          repeatCount: 1,
          connectMode: ConnectMode.none,
          finalFullPass: false,
          chainRecall: true,
        ),
      );
      final List<PlaybackUnit> chain = plan.units
          .where((PlaybackUnit u) => u.stepType == StepType.chain)
          .toList();
      expect(chain.map((PlaybackUnit u) => '${u.ref} ${u.asked}'), <String>[
        '1:1 false',
        '1:2 true',
      ]);
    });

    test('every recall-step play is asked, and no learn or connect play', () {
      final SessionPlan plan = planFor(
        const SessionConfig(
          surahNumber: 1,
          startAyah: 1,
          endAyah: 2,
          recallRounds: 1,
        ),
      );
      for (final PlaybackUnit u in plan.units) {
        expect(u.asked, u.stepType == StepType.recall, reason: '$u');
      }
    });

    test('the queue lays a gap before each asked play and nowhere else', () {
      final SessionPlan plan = planFor(
        const SessionConfig(
          surahNumber: 1,
          startAyah: 1,
          endAyah: 2,
          repeatCount: 1,
          connectMode: ConnectMode.none,
          finalFullPass: false,
          chainRecall: true,
        ),
      );
      final PlaybackQueue queue = const PlaybackQueueBuilder().build(
        plan: plan,
      );
      final List<QueueEntry> e = queue.entries;
      for (int i = 0; i < e.length; i++) {
        final QueueEntry entry = e[i];
        if (entry is! AyahQueueEntry) continue;
        final bool gapBefore = i > 0 && e[i - 1] is RecallGapEntry;
        expect(gapBefore, entry.unit.asked, reason: '${entry.unit}');
      }
      // The gap belongs to the ayah being asked, so the page veils that one.
      final RecallGapEntry gap = e.whereType<RecallGapEntry>().first;
      expect(gap.unit.ref, const AyahRef(1, 2));
    });

    test('the estimate counts one gap per asked play', () {
      const SessionConfig base = SessionConfig(
        surahNumber: 1,
        startAyah: 1,
        endAyah: 2,
        repeatCount: 1,
        connectMode: ConnectMode.none,
        finalFullPass: false,
      );
      final Map<AyahRef, Duration> clips = <AyahRef, Duration>{
        const AyahRef(1, 1): const Duration(seconds: 3),
        const AyahRef(1, 2): const Duration(seconds: 4),
      };
      final Duration without = planFor(
        base,
      ).estimatedDuration(clipDurations: clips);
      final Duration withChain = planFor(
        base.copyWith(chainRecall: true),
      ).estimatedDuration(clipDurations: clips);
      // The chain adds the cue (1:1), the gap for 1:2, and 1:2 itself.
      expect(
        withChain - without,
        const Duration(seconds: 3) +
            RecallGap.of(const Duration(seconds: 4)) +
            const Duration(seconds: 4),
      );
    });
  });
}
