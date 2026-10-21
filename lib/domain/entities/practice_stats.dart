import 'package:equatable/equatable.dart';

import '../engine/review_scheduler.dart';

/// What was practised on one day.
class PracticeDay extends Equatable {
  const PracticeDay({this.plays = 0, this.seconds = 0});

  /// Ayah plays heard.
  final int plays;

  /// Seconds the session was actually playing.
  final int seconds;

  PracticeDay plus(PracticeDay other) =>
      PracticeDay(plays: plays + other.plays, seconds: seconds + other.seconds);

  Map<String, dynamic> toMap() => <String, dynamic>{
    'plays': plays,
    'seconds': seconds,
  };

  static PracticeDay? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final Object? plays = raw['plays'];
    final Object? seconds = raw['seconds'];
    if (plays is! int || seconds is! int || plays < 0 || seconds < 0) {
      return null;
    }
    return PracticeDay(plays: plays, seconds: seconds);
  }

  @override
  List<Object?> get props => <Object?>[plays, seconds];
}

/// The plain facts of the reader's practice: what was done, added up.
///
/// Totals only, and nothing that counts what was *not* done. No run of days
/// to keep alive, no gaps marked — docs/BRAND_GUIDE.md §6: pressuring
/// someone back to worship through loss-aversion is a dark pattern, and
/// `test/core/brand_voice_test.dart` holds the line.
class PracticeStats extends Equatable {
  const PracticeStats({
    required this.daysPractised,
    required this.minutesListened,
    required this.plays,
    required this.memorizedAyahs,
  });

  final int daysPractised;
  final int minutesListened;
  final int plays;
  final int memorizedAyahs;

  factory PracticeStats.from({
    required Map<DateTime, PracticeDay> days,
    required int memorizedAyahs,
  }) {
    final Set<DateTime> practised = <DateTime>{
      for (final MapEntry<DateTime, PracticeDay> e in days.entries)
        if (e.value.plays > 0 || e.value.seconds > 0)
          ReviewScheduler.dayOf(e.key),
    };
    final int seconds = days.values.fold(
      0,
      (int a, PracticeDay d) => a + d.seconds,
    );
    return PracticeStats(
      daysPractised: practised.length,
      minutesListened: seconds ~/ 60,
      plays: days.values.fold(0, (int a, PracticeDay d) => a + d.plays),
      memorizedAyahs: memorizedAyahs,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    daysPractised,
    minutesListened,
    plays,
    memorizedAyahs,
  ];
}
