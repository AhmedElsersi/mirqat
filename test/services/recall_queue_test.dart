import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/domain/engine/repetition_plan_builder.dart';
import 'package:mirqat/domain/entities/ayah_ref.dart';
import 'package:mirqat/domain/entities/plan_step.dart';
import 'package:mirqat/domain/entities/session_config.dart';
import 'package:mirqat/domain/entities/session_plan.dart';
import 'package:mirqat/services/audio/playback_queue.dart';

SessionPlan planFor(SessionConfig config) => const RepetitionPlanBuilder()
    .build(config, surahAyahCount: 7)
    .fold((_) => throw StateError('bad config'), (SessionPlan p) => p);

void main() {
  const PlaybackQueueBuilder builder = PlaybackQueueBuilder();

  // LEARN 1 x2, RECALL 1 x2 — one ayah, so no connect steps.
  final SessionPlan plan = planFor(
    const SessionConfig(
      surahNumber: 1,
      startAyah: 1,
      endAyah: 1,
      repeatCount: 2,
      recallRounds: 2,
    ),
  );

  group('recall gaps in the queue', () {
    test('each recall play is preceded by its gap, sized from the clip', () {
      final PlaybackQueue queue = builder.build(
        plan: plan,
        recallClips: <AyahRef, Duration>{
          const AyahRef(1, 1): const Duration(seconds: 2),
        },
      );
      // RecallGap.of(2 s) = 3 s = 2400+600 ms → 3000/400 = 7.5 → 8 clips.
      final List<String> shape = <String>[
        for (final QueueEntry e in queue.entries)
          switch (e) {
            AyahQueueEntry(unit: final u) => u.stepType.name,
            RecallGapEntry() => 'gap',
            SpacerQueueEntry() => 'spacer',
            PreambleQueueEntry() => 'preamble',
          },
      ];
      expect(
        shape,
        <String>[
          'learn', 'learn', // the drill
          ...List<String>.filled(8, 'gap'), 'recall', // round one
          ...List<String>.filled(8, 'gap'), 'recall', // round two
        ],
      );
    });

    test('an unmeasured clip still gets the fallback gap', () {
      final PlaybackQueue queue = builder.build(plan: plan);
      // RecallGap.fallback = 6 s → 15 clips.
      expect(queue.entries.whereType<RecallGapEntry>().length, 30);
    });

    test('a gap is never shorter than one clip', () {
      expect(builder.recallSpacerCount(Duration.zero), greaterThan(0));
    });

    test('"reveal it" lands on the play that answers the gap', () {
      final PlaybackQueue queue = builder.build(
        plan: plan,
        recallClips: <AyahRef, Duration>{
          const AyahRef(1, 1): const Duration(seconds: 2),
        },
      );
      // Two plays, then eight gap clips, then the recall play that answers
      // them: from anywhere inside the run of gaps, the answer is index 10.
      for (int i = 2; i < 10; i++) {
        expect(queue.indexAfterRecallGap(i), 10, reason: 'from $i');
      }
      expect(queue.entries[10], isA<AyahQueueEntry>());
      // Outside a gap it is where it already is: there is nothing to cut
      // short but silence.
      expect(queue.indexAfterRecallGap(0), 0);
      expect(queue.indexAfterRecallGap(10), 10);
    });

    test('a recall gap is not a play: unitAt answers null on it', () {
      final PlaybackQueue queue = builder.build(plan: plan);
      final int firstGap = queue.entries.indexWhere(
        (QueueEntry e) => e is RecallGapEntry,
      );
      expect(queue.unitAt(firstGap), isNull);
      expect(queue.momentAt(firstGap)?.recalling, isTrue);
      expect(queue.momentAt(firstGap)?.unit.stepType, StepType.recall);
    });

    test(
      'the moment stream collapses a gap to one moment, then the answer',
      () async {
        final PlaybackQueue queue = builder.build(plan: plan);
        final Stream<int?> indices = Stream<int?>.fromIterable(
          List<int>.generate(queue.length, (int i) => i),
        );
        final List<String> moments = await queue
            .momentStreamFrom(indices)
            .map(
              (PlaybackMoment m) =>
                  '${m.recalling ? 'recall-gap' : m.unit.stepType.name} '
                  'r${m.unit.repeatIndex}',
            )
            .toList();
        expect(moments, <String>[
          'learn r1',
          'learn r2',
          'recall-gap r1',
          'recall r1',
          'recall-gap r2',
          'recall r2',
        ]);
      },
    );

    test('the unit stream keeps reporting plays only', () async {
      final PlaybackQueue queue = builder.build(plan: plan);
      final Stream<int?> indices = Stream<int?>.fromIterable(
        List<int>.generate(queue.length, (int i) => i),
      );
      final List<String> units = await queue
          .unitStreamFrom(indices)
          .map((u) => '${u.stepType.name} r${u.repeatIndex}')
          .toList();
      expect(units, <String>[
        'learn r1',
        'learn r2',
        'recall r1',
        'recall r2',
      ]);
    });

    test('a plan without recall builds the same queue as before', () {
      final SessionPlan plain = planFor(
        const SessionConfig(
          surahNumber: 1,
          startAyah: 1,
          endAyah: 2,
          repeatCount: 2,
        ),
      );
      final PlaybackQueue queue = builder.build(plan: plain);
      expect(queue.entries.whereType<RecallGapEntry>(), isEmpty);
    });
  });
}
