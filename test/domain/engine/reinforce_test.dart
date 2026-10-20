import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/error/failures.dart';
import 'package:mirqat/domain/engine/repetition_plan_builder.dart';
import 'package:mirqat/domain/entities/ayah_ref.dart';
import 'package:mirqat/domain/entities/plan_step.dart';
import 'package:mirqat/domain/entities/playback_unit.dart';
import 'package:mirqat/domain/entities/session_config.dart';
import 'package:mirqat/domain/entities/session_plan.dart';
import 'package:mirqat/features/session/session_request.dart';

const RepetitionPlanBuilder builder = RepetitionPlanBuilder();

SessionPlan planFor(SessionConfig config, Set<AyahRef> reinforce) => builder
    .build(config, surahAyahCount: 7, reinforce: reinforce)
    .fold(
      (Failure f) => fail('expected a plan, got: ${f.message}'),
      (SessionPlan p) => p,
    );

void main() {
  group('reinforcing the ayahs the reader stumbles at', () {
    test('adds the extra repeats to exactly those learn steps', () {
      final SessionPlan plan = planFor(
        const SessionConfig(
          surahNumber: 1,
          startAyah: 1,
          endAyah: 3,
          repeatCount: 2,
        ),
        <AyahRef>{const AyahRef(1, 2)},
      );
      final Map<int, int> learn = <int, int>{
        for (final LearnStep s in plan.steps.whereType<LearnStep>())
          s.ayah: s.repeats,
      };
      expect(learn, <int, int>{
        1: 2,
        2: 2 + RepetitionPlanBuilder.reinforceExtra,
        3: 2,
      });
      // The joins are untouched: it is the ayah that is weak, not the block.
      for (final ConnectStep c in plan.steps.whereType<ConnectStep>()) {
        expect(c.repeats, 2);
      }
      // Each play of the reinforced step counts out of its own total.
      final List<PlaybackUnit> two = plan.units
          .where(
            (PlaybackUnit u) =>
                u.stepType == StepType.learn && u.ayahNumber == 2,
          )
          .toList();
      expect(two.length, 2 + RepetitionPlanBuilder.reinforceExtra);
      expect(two.last.totalRepeats, 2 + RepetitionPlanBuilder.reinforceExtra);
    });

    test('a mark outside the range changes nothing', () {
      const SessionConfig config = SessionConfig(
        surahNumber: 1,
        startAyah: 1,
        endAyah: 3,
      );
      expect(
        planFor(config, <AyahRef>{const AyahRef(1, 6), const AyahRef(9, 1)}),
        planFor(config, const <AyahRef>{}),
      );
    });

    test('continuous mode, with no per-ayah step, is unchanged', () {
      const SessionConfig config = SessionConfig(
        surahNumber: 1,
        startAyah: 1,
        endAyah: 3,
        connectMode: ConnectMode.continuous,
      );
      expect(
        planFor(config, <AyahRef>{const AyahRef(1, 2)}).steps,
        planFor(config, const <AyahRef>{}).steps,
      );
    });
  });

  group('a session preset', () {
    const SessionConfig base = SessionConfig(
      surahNumber: 1,
      startAyah: 1,
      endAyah: 3,
      repeatCount: 5,
      playbackSpeed: 1.25,
      recallRounds: 2,
    );

    test('an empty preset keeps every default', () {
      expect(const SessionPreset().applyTo(base), base);
    });

    test('lays its fields over the defaults and keeps the rest', () {
      final SessionConfig c = const SessionPreset(
        repeatCount: 1,
        connectMode: ConnectMode.continuous,
        recallRounds: 0,
        chainRecall: true,
      ).applyTo(base);
      expect(c.repeatCount, 1);
      expect(c.connectMode, ConnectMode.continuous);
      expect(c.recallRounds, 0);
      expect(c.chainRecall, isTrue);
      expect(c.playbackSpeed, 1.25);
      expect(c.start, base.start);
      expect(c.end, base.end);
      // The closing pass follows the new mode's own default.
      expect(c.finalFullPass, ConnectMode.continuous.defaultFinalFullPass);
    });

    test('values out of bounds are held to them', () {
      final SessionConfig c = const SessionPreset(
        repeatCount: 0,
        recallRounds: 99,
      ).applyTo(base);
      expect(c.repeatCount, SessionConfig.minRepeatCount);
      expect(c.recallRounds, SessionConfig.maxRecallRounds);
    });
  });
}
