import 'package:equatable/equatable.dart';

import 'ayah_ref.dart';

enum StepType { learn, connect }

/// One instruction in a session plan: play this ayah, or this block of ayahs,
/// [repeats] times.
///
/// A block is a run of consecutive ayahs and may cross from one surah into
/// the next, so it is addressed by [AyahRef]. The plain ayah numbers are kept
/// beside the refs because inside one surah — the usual session — they are
/// all anyone needs to say.
sealed class PlanStep extends Equatable {
  const PlanStep({required this.repeats});

  /// How many times the step's block is played through.
  final int repeats;

  StepType get type;

  /// Ayahs played once per repetition, in order.
  List<AyahRef> get refs;

  AyahRef get fromRef => refs.first;
  AyahRef get toRef => refs.last;

  /// First ayah of the block this step plays, as a number within its surah.
  int get fromAyah => fromRef.ayah;

  /// Last ayah of the block this step plays, inclusive, within its surah.
  int get toAyah => toRef.ayah;

  /// Whether the block runs over a surah boundary.
  bool get spansSurahs => fromRef.surah != toRef.surah;

  /// The block's ayah numbers, in order. Across a surah boundary the numbers
  /// start again, which is why [refs] is what playback reads.
  List<int> get ayahs => <int>[for (final AyahRef r in refs) r.ayah];

  /// Ayah plays contributed by this step.
  int get unitCount => refs.length * repeats;
}

/// Drill a single ayah.
class LearnStep extends PlanStep {
  const LearnStep({
    required this.surah,
    required this.ayah,
    required super.repeats,
  });

  final int surah;
  final int ayah;

  @override
  StepType get type => StepType.learn;

  @override
  List<AyahRef> get refs => <AyahRef>[AyahRef(surah, ayah)];

  @override
  List<Object?> get props => <Object?>[surah, ayah, repeats];
}

/// Join a block of ayahs and play them through together.
class ConnectStep extends PlanStep {
  const ConnectStep({required this.refs, required super.repeats});

  @override
  final List<AyahRef> refs;

  /// The block's first and last ayah numbers, for the single-surah case.
  int get from => fromAyah;
  int get to => toAyah;

  @override
  StepType get type => StepType.connect;

  @override
  List<Object?> get props => <Object?>[fromRef, toRef, refs.length, repeats];
}
