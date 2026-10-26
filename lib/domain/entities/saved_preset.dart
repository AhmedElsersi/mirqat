import 'package:equatable/equatable.dart';

import 'session_config.dart';

/// A way of working the reader named and saved from the session form — how
/// many repeats, how ayahs are joined, how much is asked back — so their own
/// routine is one tap, beside the four the app comes with.
class SavedPreset extends Equatable {
  const SavedPreset({
    required this.name,
    required this.repeatCount,
    required this.connectMode,
    required this.recallRounds,
    required this.chainRecall,
  });

  /// The values of [config] that make a way of working, under [name].
  factory SavedPreset.of(String name, SessionConfig config) => SavedPreset(
    name: name,
    repeatCount: config.repeatCount,
    connectMode: config.connectMode,
    recallRounds: config.recallRounds,
    chainRecall: config.chainRecall,
  );

  /// Long enough for "Fajr review", short enough to sit on a chip.
  static const int maxNameLength = 24;

  /// More than this and the row of chips is a list to read.
  static const int maxSaved = 6;

  final String name;
  final int repeatCount;
  final ConnectMode connectMode;
  final int recallRounds;
  final bool chainRecall;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'name': name,
    'repeatCount': repeatCount,
    'connectMode': connectMode.name,
    'recallRounds': recallRounds,
    'chainRecall': chainRecall,
  };

  /// Read forgivingly: a preset that cannot be read is skipped, never a
  /// failure of the settings around it. Counts out of range are brought in.
  static SavedPreset? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final Object? name = raw['name'];
    final Object? repeats = raw['repeatCount'];
    final Object? recall = raw['recallRounds'];
    final ConnectMode? mode = ConnectMode.values
        .where((ConnectMode m) => m.name == raw['connectMode'])
        .firstOrNull;
    if (name is! String || name.trim().isEmpty) return null;
    if (repeats is! int || recall is! int || mode == null) return null;
    return SavedPreset(
      name: name.trim(),
      repeatCount: repeats.clamp(
        SessionConfig.minRepeatCount,
        SessionConfig.maxRepeatCount,
      ),
      connectMode: mode,
      recallRounds: recall.clamp(
        SessionConfig.minRecallRounds,
        SessionConfig.maxRecallRounds,
      ),
      chainRecall: raw['chainRecall'] == true,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    name,
    repeatCount,
    connectMode,
    recallRounds,
    chainRecall,
  ];
}
