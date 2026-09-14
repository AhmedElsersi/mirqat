import 'package:dartz/dartz.dart';

import '../../core/error/exceptions.dart';
import '../../core/error/failures.dart';
import '../entities/playback_unit.dart';
import '../entities/plan_step.dart';
import '../entities/session_config.dart';
import '../entities/session_plan.dart';

/// Turns a [SessionConfig] into an ordered plan of steps and the flat queue of
/// ayah plays behind it.
///
/// Pure Dart with zero Flutter imports, so the whole thing is unit-testable
/// (CLAUDE.md A.3).
class RepetitionPlanBuilder {
  const RepetitionPlanBuilder();

  /// Builds the plan, or a [SessionConfigFailure] describing why the config is
  /// unusable.
  ///
  /// [surahAyahCount] comes from the catalog — the range is never checked
  /// against a hardcoded constant (CLAUDE.md A.2 rule 2).
  Either<Failure, SessionPlan> build(
    SessionConfig config, {
    required int surahAyahCount,
  }) {
    final String? error = _validate(config, surahAyahCount);
    if (error != null) {
      return Left<Failure, SessionPlan>(SessionConfigFailure(error));
    }

    final List<PlanStep> steps = _buildSteps(config);
    return Right<Failure, SessionPlan>(
      SessionPlan(config: config, steps: steps, units: flatten(steps, config)),
    );
  }

  /// The throwing form, for call sites that have already validated the config.
  SessionPlan buildOrThrow(
    SessionConfig config, {
    required int surahAyahCount,
  }) => build(config, surahAyahCount: surahAyahCount).fold(
    (Failure f) => throw SessionConfigException(f.message),
    (SessionPlan plan) => plan,
  );

  String? _validate(SessionConfig config, int surahAyahCount) {
    if (surahAyahCount < 1) {
      return 'Surah ${config.surahNumber} reports $surahAyahCount ayahs, so no '
          'session can be built from it.';
    }
    if (config.startAyah < 1) {
      return 'startAyah must be at least 1, got ${config.startAyah}.';
    }
    if (config.startAyah > config.endAyah) {
      return 'Ayah range is inverted: startAyah ${config.startAyah} is after '
          'endAyah ${config.endAyah}.';
    }
    if (config.endAyah > surahAyahCount) {
      return 'Ayah range ${config.startAyah}..${config.endAyah} is outside '
          'surah ${config.surahNumber}, which has $surahAyahCount ayahs.';
    }
    if (config.repeatCount < SessionConfig.minRepeatCount ||
        config.repeatCount > SessionConfig.maxRepeatCount) {
      return 'repeatCount must be between ${SessionConfig.minRepeatCount} and '
          '${SessionConfig.maxRepeatCount}, got ${config.repeatCount}.';
    }
    if (config.playbackSpeed < SessionConfig.minPlaybackSpeed ||
        config.playbackSpeed > SessionConfig.maxPlaybackSpeed) {
      return 'playbackSpeed must be between '
          '${SessionConfig.minPlaybackSpeed} and '
          '${SessionConfig.maxPlaybackSpeed}, got ${config.playbackSpeed}.';
    }
    if (config.intraBlockPauseMs < 0 ||
        config.betweenRepeatPauseMs < 0 ||
        config.betweenStepsPauseMs < 0) {
      return 'Pause lengths must not be negative, got '
          '${config.intraBlockPauseMs}/${config.betweenRepeatPauseMs}/'
          '${config.betweenStepsPauseMs} ms.';
    }
    return null;
  }

  /// For [ConnectMode.continuous] the whole range is one block:
  ///
  /// ```
  /// ConnectStep(startAyah, endAyah)   // repeated repeatCount times
  /// ```
  ///
  /// For the drill modes it is the talqeen loop:
  ///
  /// ```
  /// for i in startAyah..endAyah:
  ///     LearnStep(i)
  ///     if i > startAyah: ConnectStep(...)
  /// if finalFullPass:  ConnectStep(startAyah, endAyah)
  /// ```
  ///
  /// The connect step after the first learn step is never emitted — joining a
  /// single ayah to nothing is a no-op.
  List<PlanStep> _buildSteps(SessionConfig config) {
    final int n = config.repeatCount;
    final List<PlanStep> steps = <PlanStep>[];

    // Continuous is a different shape, not another branch of the loop below:
    // the range is recited straight through and the whole pass repeats, so
    // there are no per-ayah drill steps to emit. One step, and `flatten` turns
    // its `repeats` into the repeated passes.
    if (config.connectMode == ConnectMode.continuous) {
      steps.add(
        ConnectStep(from: config.startAyah, to: config.endAyah, repeats: n),
      );
      if (config.finalFullPass && config.endAyah > config.startAyah) {
        steps.add(
          ConnectStep(from: config.startAyah, to: config.endAyah, repeats: n),
        );
      }
      return List<PlanStep>.unmodifiable(steps);
    }

    for (int i = config.startAyah; i <= config.endAyah; i++) {
      steps.add(LearnStep(ayah: i, repeats: n));

      if (i == config.startAyah) continue;

      switch (config.connectMode) {
        case ConnectMode.cumulative:
          steps.add(ConnectStep(from: config.startAyah, to: i, repeats: n));
        case ConnectMode.none:
          break;
        case ConnectMode.continuous:
          // Unreachable: handled above, before the loop.
          break;
      }
    }

    // A full pass over a single-ayah range would be the same no-op as the
    // skipped first connect step, so it is suppressed too.
    if (config.finalFullPass && config.endAyah > config.startAyah) {
      steps.add(
        ConnectStep(from: config.startAyah, to: config.endAyah, repeats: n),
      );
    }

    return List<PlanStep>.unmodifiable(steps);
  }

  /// Expands [steps] into the flat queue: one [PlaybackUnit] per ayah play.
  List<PlaybackUnit> flatten(List<PlanStep> steps, SessionConfig config) {
    final List<PlaybackUnit> units = <PlaybackUnit>[];

    for (int stepIndex = 0; stepIndex < steps.length; stepIndex++) {
      final PlanStep step = steps[stepIndex];
      final List<int> ayahs = step.ayahs;

      for (int repeat = 1; repeat <= step.repeats; repeat++) {
        for (int position = 0; position < ayahs.length; position++) {
          final bool lastOfRepeat = position == ayahs.length - 1;
          units.add(
            PlaybackUnit(
              stepIndex: stepIndex,
              stepType: step.type,
              ayahNumber: ayahs[position],
              repeatIndex: repeat,
              totalRepeats: step.repeats,
              blockFrom: step.fromAyah,
              blockTo: step.toAyah,
              isLastUnitOfRepeat: lastOfRepeat,
              isLastUnitOfStep: lastOfRepeat && repeat == step.repeats,
            ),
          );
        }
      }
    }

    return List<PlaybackUnit>.unmodifiable(units);
  }
}
