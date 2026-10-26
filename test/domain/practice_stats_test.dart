import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/domain/entities/practice_stats.dart';

void main() {
  const PracticeDay some = PracticeDay(plays: 10, seconds: 600);

  PracticeStats stats(List<DateTime> days, {int memorized = 0}) =>
      PracticeStats.from(
        days: <DateTime, PracticeDay>{for (final DateTime d in days) d: some},
        memorizedAyahs: memorized,
      );

  test('nothing practised: all nought', () {
    final PracticeStats s = stats(<DateTime>[]);
    expect(s.daysPractised, 0);
    expect(s.minutesListened, 0);
    expect(s.plays, 0);
  });

  test('totals add up, whatever the gaps between the days', () {
    final PracticeStats s = stats(<DateTime>[
      DateTime(2026, 10, 1),
      DateTime(2026, 10, 2, 23),
      DateTime(2026, 10, 31),
    ], memorized: 42);
    expect(s.daysPractised, 3);
    expect(s.minutesListened, 30);
    expect(s.plays, 30);
    expect(s.memorizedAyahs, 42);
  });

  test('a day with nothing in it is not a day practised', () {
    final PracticeStats s = PracticeStats.from(
      days: <DateTime, PracticeDay>{DateTime(2026, 11, 2): const PracticeDay()},
      memorizedAyahs: 0,
    );
    expect(s.daysPractised, 0);
  });

  test('a stored day reads forgivingly', () {
    expect(PracticeDay.fromMap(some.toMap()), some);
    expect(
      PracticeDay.fromMap(<String, Object?>{'plays': -1, 'seconds': 0}),
      isNull,
    );
    expect(PracticeDay.fromMap('day'), isNull);
  });
}
