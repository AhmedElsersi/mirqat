import 'package:dartz/dartz.dart';

import '../../core/error/exceptions.dart';
import '../../core/error/failures.dart';
import '../entities/ayah_ref.dart';
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
  /// The ayah counts come from the catalog — the range is never checked
  /// against a hardcoded constant (CLAUDE.md A.2 rule 2). A session inside one
  /// surah passes [surahAyahCount]; one that runs on into later surahs passes
  /// [ayahCounts], surah number to ayah count, for every surah it touches.
  Either<Failure, SessionPlan> build(
    SessionConfig config, {
    int? surahAyahCount,
    Map<int, int>? ayahCounts,
  }) {
    final Map<int, int> counts = <int, int>{
      config.surahNumber: ?surahAyahCount,
      ...?ayahCounts,
    };
    final String? error = _validate(config, counts);
    if (error != null) {
      return Left<Failure, SessionPlan>(SessionConfigFailure(error));
    }

    final List<PlanStep> steps = _buildSteps(config, rangeOf(config, counts));
    return Right<Failure, SessionPlan>(
      SessionPlan(config: config, steps: steps, units: flatten(steps, config)),
    );
  }

  /// The throwing form, for call sites that have already validated the config.
  SessionPlan buildOrThrow(
    SessionConfig config, {
    int? surahAyahCount,
    Map<int, int>? ayahCounts,
  }) => build(config, surahAyahCount: surahAyahCount, ayahCounts: ayahCounts)
      .fold(
        (Failure f) => throw SessionConfigException(f.message),
        (SessionPlan plan) => plan,
      );

  /// Every ayah of the range, in mushaf order: the rest of the first surah,
  /// the whole of any surah between, and the last surah up to the end ayah.
  ///
  /// A surah's basmala is not in here and never will be — it is not an ayah
  /// (except where the catalog numbers it as one, and then it is simply
  /// ayah 1). The queue plays it as a preamble ahead of the surah.
  static List<AyahRef> rangeOf(SessionConfig config, Map<int, int> ayahCounts) {
    final List<AyahRef> range = <AyahRef>[];
    for (int s = config.surahNumber; s <= config.endSurahNumber; s++) {
      final int first = s == config.surahNumber ? config.startAyah : 1;
      final int last = s == config.endSurahNumber
          ? config.endAyah
          : ayahCounts[s]!;
      for (int a = first; a <= last; a++) {
        range.add(AyahRef(s, a));
      }
    }
    return List<AyahRef>.unmodifiable(range);
  }

  String? _validate(SessionConfig config, Map<int, int> ayahCounts) {
    if (config.endSurahNumber < config.surahNumber) {
      return 'The range runs backwards: it starts in surah '
          '${config.surahNumber} and ends in surah ${config.endSurahNumber}. '
          'A session only ever runs forward.';
    }
    for (int s = config.surahNumber; s <= config.endSurahNumber; s++) {
      final int? count = ayahCounts[s];
      if (count == null) {
        return 'No ayah count was supplied for surah $s, which the range '
            '${config.start}..${config.end} runs through.';
      }
      if (count < 1) {
        return 'Surah $s reports $count ayahs, so no session can be built '
            'from it.';
      }
    }
    if (config.startAyah < 1) {
      return 'startAyah must be at least 1, got ${config.startAyah}.';
    }
    if (config.endAyah < 1) {
      return 'endAyah must be at least 1, got ${config.endAyah}.';
    }
    if (!config.spansSurahs && config.startAyah > config.endAyah) {
      return 'Ayah range is inverted: startAyah ${config.startAyah} is after '
          'endAyah ${config.endAyah}.';
    }
    if (config.startAyah > ayahCounts[config.surahNumber]!) {
      return 'Ayah range ${config.start}..${config.end} starts outside surah '
          '${config.surahNumber}, which has '
          '${ayahCounts[config.surahNumber]} ayahs.';
    }
    if (config.endAyah > ayahCounts[config.endSurahNumber]!) {
      return 'Ayah range ${config.startAyah}..${config.endAyah} is outside '
          'surah ${config.endSurahNumber}, which has '
          '${ayahCounts[config.endSurahNumber]} ayahs.';
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
  List<PlanStep> _buildSteps(SessionConfig config, List<AyahRef> range) {
    final int n = config.repeatCount;
    final List<PlanStep> steps = <PlanStep>[];

    // Continuous is a different shape, not another branch of the loop below:
    // the range is recited straight through and the whole pass repeats, so
    // there are no per-ayah drill steps to emit. One step, and `flatten` turns
    // its `repeats` into the repeated passes.
    if (config.connectMode == ConnectMode.continuous) {
      steps.add(ConnectStep(refs: range, repeats: n));
      if (config.finalFullPass && range.length > 1) {
        steps.add(ConnectStep(refs: range, repeats: n));
      }
      return List<PlanStep>.unmodifiable(steps);
    }

    // The joining is over the *range*, not over a surah: the block after the
    // first ayah of a second surah reaches all the way back to where the
    // session began, exactly as it would inside one surah.
    for (int i = 0; i < range.length; i++) {
      steps.add(
        LearnStep(surah: range[i].surah, ayah: range[i].ayah, repeats: n),
      );

      if (i == 0) continue;

      switch (config.connectMode) {
        case ConnectMode.cumulative:
          steps.add(ConnectStep(refs: range.sublist(0, i + 1), repeats: n));
        case ConnectMode.none:
          break;
        case ConnectMode.continuous:
          // Unreachable: handled above, before the loop.
          break;
      }
    }

    // A full pass over a single-ayah range would be the same no-op as the
    // skipped first connect step, so it is suppressed too.
    if (config.finalFullPass && range.length > 1) {
      steps.add(ConnectStep(refs: range, repeats: n));
    }

    return List<PlanStep>.unmodifiable(steps);
  }

  /// Expands [steps] into the flat queue: one [PlaybackUnit] per ayah play.
  List<PlaybackUnit> flatten(List<PlanStep> steps, SessionConfig config) {
    final List<PlaybackUnit> units = <PlaybackUnit>[];

    for (int stepIndex = 0; stepIndex < steps.length; stepIndex++) {
      final PlanStep step = steps[stepIndex];
      final List<AyahRef> refs = step.refs;

      for (int repeat = 1; repeat <= step.repeats; repeat++) {
        for (int position = 0; position < refs.length; position++) {
          final bool lastOfRepeat = position == refs.length - 1;
          units.add(
            PlaybackUnit(
              stepIndex: stepIndex,
              stepType: step.type,
              surahNumber: refs[position].surah,
              ayahNumber: refs[position].ayah,
              repeatIndex: repeat,
              totalRepeats: step.repeats,
              blockFrom: step.fromAyah,
              blockTo: step.toAyah,
              blockFromSurah: step.fromRef.surah,
              blockToSurah: step.toRef.surah,
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
