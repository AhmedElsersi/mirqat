import 'package:equatable/equatable.dart';

import 'ayah_ref.dart';
import 'session_config.dart';

/// A session the reader did not finish and did not stop: the app was closed
/// under it, or the screen left. Enough to pick it up again — the settings
/// it ran with, who recited, and the ayah it had reached.
class InterruptedSession extends Equatable {
  const InterruptedSession({
    required this.config,
    required this.reciterId,
    required this.at,
    required this.savedAt,
  });

  final SessionConfig config;
  final String reciterId;

  /// The ayah being recited when it was last saved. Resuming starts its
  /// drill from the top, as carrying on after a change does.
  final AyahRef at;
  final DateTime savedAt;

  /// How long an interrupted session is offered back. After that it is an
  /// old session, not an interrupted one.
  static const Duration offeredFor = Duration(hours: 24);

  bool isFresh(DateTime now) =>
      !savedAt.isAfter(now) && now.difference(savedAt) < offeredFor;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'config': config.toMap(),
    'reciterId': reciterId,
    'at': <int>[at.surah, at.ayah],
    'savedAt': savedAt.toIso8601String(),
  };

  static InterruptedSession? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final SessionConfig? config = SessionConfig.fromMap(raw['config']);
    final Object? reciter = raw['reciterId'];
    final Object? at = raw['at'];
    final Object? saved = raw['savedAt'];
    if (config == null ||
        reciter is! String ||
        at is! List ||
        at.length != 2 ||
        at[0] is! int ||
        at[1] is! int ||
        saved is! String) {
      return null;
    }
    final DateTime? savedAt = DateTime.tryParse(saved);
    if (savedAt == null) return null;
    return InterruptedSession(
      config: config,
      reciterId: reciter,
      at: AyahRef(at[0] as int, at[1] as int),
      savedAt: savedAt,
    );
  }

  @override
  List<Object?> get props => <Object?>[config, reciterId, at, savedAt];
}
