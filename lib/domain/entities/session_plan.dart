import 'package:equatable/equatable.dart';

import 'ayah_ref.dart';
import 'playback_unit.dart';
import 'plan_step.dart';
import 'session_config.dart';

/// A built session: the ordered steps, and the flat queue of ayah plays they
/// expand into.
class SessionPlan extends Equatable {
  const SessionPlan({
    required this.config,
    required this.steps,
    required this.units,
  });

  final SessionConfig config;
  final List<PlanStep> steps;

  /// Every ayah play in order. `units.length` is the number of recitations the
  /// session will contain.
  final List<PlaybackUnit> units;

  int get stepCount => steps.length;
  int get unitCount => units.length;

  /// Index of the first unit belonging to [stepIndex].
  int firstUnitOfStep(int stepIndex) {
    for (int i = 0; i < units.length; i++) {
      if (units[i].stepIndex == stepIndex) return i;
    }
    throw RangeError.index(stepIndex, steps, 'stepIndex');
  }

  /// The surahs this plan recites from, in order.
  List<int> get surahNumbers {
    final List<int> out = <int>[];
    for (final PlanStep step in steps) {
      for (final AyahRef r in step.refs) {
        if (!out.contains(r.surah)) out.add(r.surah);
      }
    }
    return out;
  }

  /// Where a listener who was on [ref] should pick this plan up: the first
  /// play of that ayah, which is the start of its drill. Null when the plan
  /// never recites it — the range no longer holds it — and the only honest
  /// place to resume is the beginning.
  int? firstUnitOf(AyahRef ref) {
    for (int i = 0; i < units.length; i++) {
      if (units[i].ref == ref) return i;
    }
    return null;
  }

  /// Wall-clock estimate for the whole session.
  ///
  /// [clipDurations] maps each ayah to the real duration of its clip, so the
  /// summary shown before a session is measured rather than guessed. Pauses
  /// are queued as audio spacers, so playback speed scales them along with the
  /// recitation.
  Duration estimatedDuration({required Map<AyahRef, Duration> clipDurations}) {
    int micros = 0;

    for (int i = 0; i < units.length; i++) {
      final PlaybackUnit unit = units[i];
      final Duration? clip = clipDurations[unit.ref];
      if (clip == null) {
        throw ArgumentError(
          'No duration supplied for ayah ${unit.ref}; cannot estimate '
          'the session length without it.',
        );
      }
      micros += clip.inMicroseconds;

      if (i == units.length - 1) break;
      micros += gapAfter(unit).inMicroseconds;
    }

    return Duration(microseconds: (micros / config.playbackSpeed).round());
  }

  /// The silence that follows [unit] before whatever comes next. The playback
  /// queue realises this with spacer clips; the estimate above just adds it up.
  Duration gapAfter(PlaybackUnit unit) {
    if (unit.isLastUnitOfStep) {
      return Duration(milliseconds: config.betweenStepsPauseMs);
    }
    if (unit.isLastUnitOfRepeat) {
      return Duration(milliseconds: config.betweenRepeatPauseMs);
    }
    return Duration(milliseconds: config.intraBlockPauseMs);
  }

  @override
  List<Object?> get props => <Object?>[config, steps, units];
}
