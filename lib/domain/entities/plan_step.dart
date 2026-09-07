import 'package:equatable/equatable.dart';

enum StepType { learn, connect }

/// One instruction in a session plan: play this ayah, or this block of ayahs,
/// [repeats] times.
sealed class PlanStep extends Equatable {
  const PlanStep({required this.repeats});

  /// How many times the step's block is played through.
  final int repeats;

  StepType get type;

  /// First ayah of the block this step plays.
  int get fromAyah;

  /// Last ayah of the block this step plays, inclusive.
  int get toAyah;

  /// Ayahs played once per repetition, in order.
  List<int> get ayahs =>
      <int>[for (int a = fromAyah; a <= toAyah; a++) a];

  /// Ayah plays contributed by this step.
  int get unitCount => ayahs.length * repeats;
}

/// Drill a single ayah.
class LearnStep extends PlanStep {
  const LearnStep({required this.ayah, required super.repeats});

  final int ayah;

  @override
  StepType get type => StepType.learn;

  @override
  int get fromAyah => ayah;

  @override
  int get toAyah => ayah;

  @override
  List<Object?> get props => <Object?>[ayah, repeats];
}

/// Join a block of ayahs and play them through together.
class ConnectStep extends PlanStep {
  const ConnectStep({
    required this.from,
    required this.to,
    required super.repeats,
  });

  final int from;
  final int to;

  @override
  StepType get type => StepType.connect;

  @override
  int get fromAyah => from;

  @override
  int get toAyah => to;

  @override
  List<Object?> get props => <Object?>[from, to, repeats];
}
