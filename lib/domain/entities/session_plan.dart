import 'package:equatable/equatable.dart';

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

  /// Wall-clock estimate for the whole session.
  ///
  /// [ayahDurations] maps ayah number to the real duration of its clip, so the
  /// summary shown before a session is measured rather than guessed. Pauses
  /// are queued as audio spacers, so playback speed scales them along with the
  /// recitation.
  Duration estimatedDuration({required Map<int, Duration> ayahDurations}) {
    int micros = 0;

    for (int i = 0; i < units.length; i++) {
      final PlaybackUnit unit = units[i];
      final Duration? clip = ayahDurations[unit.ayahNumber];
      if (clip == null) {
        throw ArgumentError(
          'No duration supplied for ayah ${unit.ayahNumber}; cannot estimate '
          'the session length without it.',
        );
      }
      micros += clip.inMicroseconds;

      if (i == units.length - 1) break;
      micros += _gapAfter(unit).inMicroseconds;
    }

    return Duration(microseconds: (micros / config.playbackSpeed).round());
  }

  /// The silence that follows [unit] before whatever comes next.
  Duration _gapAfter(PlaybackUnit unit) {
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
