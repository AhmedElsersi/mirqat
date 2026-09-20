import 'package:equatable/equatable.dart';

import 'ayah_ref.dart';
import 'plan_step.dart';

/// One ayah played once — the atom of the playback queue.
///
/// The player walks a flat list of these; the step structure above it exists
/// only for the UI.
class PlaybackUnit extends Equatable {
  const PlaybackUnit({
    required this.stepIndex,
    required this.stepType,
    required this.surahNumber,
    required this.ayahNumber,
    required this.repeatIndex,
    required this.totalRepeats,
    required this.blockFrom,
    required this.blockTo,
    int? blockFromSurah,
    int? blockToSurah,
    required this.isLastUnitOfRepeat,
    required this.isLastUnitOfStep,
  }) : blockFromSurah = blockFromSurah ?? surahNumber,
       blockToSurah = blockToSurah ?? surahNumber;

  /// Index into [SessionPlan.steps].
  final int stepIndex;

  final StepType stepType;

  /// The surah of the ayah this unit plays. A session may run from one surah
  /// into the next, so an ayah number alone does not say which clip this is.
  final int surahNumber;

  /// The ayah this unit plays, numbered within [surahNumber].
  final int ayahNumber;

  /// Which repetition of the step this is, 1-based.
  final int repeatIndex;

  /// Always equal to the config's `repeatCount`.
  final int totalRepeats;

  /// Block bounds of the owning step, for highlighting the whole block while
  /// emphasising the ayah currently sounding.
  final int blockFrom;
  final int blockTo;

  /// The surahs [blockFrom] and [blockTo] are numbered in. Both default to
  /// [surahNumber]: a block only reaches into another surah when the session
  /// does.
  final int blockFromSurah;
  final int blockToSurah;

  AyahRef get ref => AyahRef(surahNumber, ayahNumber);
  AyahRef get blockFromRef => AyahRef(blockFromSurah, blockFrom);
  AyahRef get blockToRef => AyahRef(blockToSurah, blockTo);

  final bool isLastUnitOfRepeat;
  final bool isLastUnitOfStep;

  @override
  List<Object?> get props => <Object?>[
    stepIndex,
    stepType,
    surahNumber,
    ayahNumber,
    repeatIndex,
    totalRepeats,
    blockFrom,
    blockTo,
    blockFromSurah,
    blockToSurah,
    isLastUnitOfRepeat,
    isLastUnitOfStep,
  ];

  @override
  String toString() =>
      'PlaybackUnit(step $stepIndex ${stepType.name} ayah $ref '
      'repeat $repeatIndex/$totalRepeats block $blockFromRef-$blockToRef)';
}
