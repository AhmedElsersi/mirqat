import 'package:equatable/equatable.dart';

import 'plan_step.dart';

/// One ayah played once — the atom of the playback queue.
///
/// The player walks a flat list of these; the step structure above it exists
/// only for the UI.
class PlaybackUnit extends Equatable {
  const PlaybackUnit({
    required this.stepIndex,
    required this.stepType,
    required this.ayahNumber,
    required this.repeatIndex,
    required this.totalRepeats,
    required this.blockFrom,
    required this.blockTo,
    required this.isLastUnitOfRepeat,
    required this.isLastUnitOfStep,
  });

  /// Index into [SessionPlan.steps].
  final int stepIndex;

  final StepType stepType;

  /// The ayah this unit plays.
  final int ayahNumber;

  /// Which repetition of the step this is, 1-based.
  final int repeatIndex;

  /// Always equal to the config's `repeatCount`.
  final int totalRepeats;

  /// Block bounds of the owning step, for highlighting the whole block while
  /// emphasising the ayah currently sounding.
  final int blockFrom;
  final int blockTo;

  final bool isLastUnitOfRepeat;
  final bool isLastUnitOfStep;

  @override
  List<Object?> get props => <Object?>[
    stepIndex,
    stepType,
    ayahNumber,
    repeatIndex,
    totalRepeats,
    blockFrom,
    blockTo,
    isLastUnitOfRepeat,
    isLastUnitOfStep,
  ];

  @override
  String toString() =>
      'PlaybackUnit(step $stepIndex ${stepType.name} ayah $ayahNumber '
      'repeat $repeatIndex/$totalRepeats block $blockFrom-$blockTo)';
}
