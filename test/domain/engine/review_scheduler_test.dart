import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/domain/engine/review_scheduler.dart';
import 'package:mirqat/domain/entities/ayah_ref.dart';
import 'package:mirqat/domain/entities/review_card.dart';

void main() {
  const ReviewScheduler scheduler = ReviewScheduler();
  const AyahRef a = AyahRef(67, 1);
  const AyahRef b = AyahRef(67, 5);
  final DateTime monday = DateTime(2026, 10, 19, 21, 30);

  ReviewCard started([Grade grade = Grade.solid]) =>
      scheduler.start(from: a, to: b, grade: grade, now: monday);

  group('the ladder', () {
    test('a range graded for the first time is due tomorrow, whatever the '
        'grade', () {
      for (final Grade g in Grade.values) {
        final ReviewCard c = started(g);
        expect(c.step, 0);
        expect(c.due, DateTime(2026, 10, 20));
        expect(c.created, DateTime(2026, 10, 19));
        expect(c.lastGrade, g);
      }
    });

    test('solid climbs a rung: 1, 3, 7, 14, 30, 90 — and stays at the top', () {
      ReviewCard c = started();
      DateTime now = monday;
      final List<int> gaps = <int>[];
      for (int i = 0; i < 8; i++) {
        now = c.due;
        c = scheduler.grade(c, Grade.solid, now);
        gaps.add(ReviewScheduler.daysBetween(now, c.due));
      }
      expect(gaps, <int>[3, 7, 14, 30, 90, 90, 90, 90]);
    });

    test('shaky stays on its rung', () {
      final ReviewCard c = scheduler.grade(
        scheduler.grade(started(), Grade.solid, monday),
        Grade.shaky,
        monday,
      );
      expect(c.step, 1);
      expect(c.due, DateTime(2026, 10, 22));
    });

    test('forgot starts again, due tomorrow', () {
      ReviewCard c = started();
      for (int i = 0; i < 4; i++) {
        c = scheduler.grade(c, Grade.solid, monday);
      }
      c = scheduler.grade(c, Grade.forgot, monday);
      expect(c.step, 0);
      expect(c.due, DateTime(2026, 10, 20));
      expect(c.created, DateTime(2026, 10, 19), reason: 'its age is its age');
    });

    test('a gap is counted in calendar days, even across a clock change', () {
      // A week that crosses the EU's spring change: in a zone with daylight
      // saving, local midnights a week apart are 167 hours apart, which
      // `inDays` alone calls six days.
      expect(
        ReviewScheduler.daysBetween(
          DateTime(2029, 3, 22),
          DateTime(2029, 3, 29),
        ),
        7,
      );
      expect(
        ReviewScheduler.daysBetween(
          DateTime(2026, 10, 19, 23),
          DateTime(2026, 10, 20, 1),
        ),
        1,
      );
    });

    test(
      'days are calendar days: a daylight-saving change cannot shift one',
      () {
        // Whatever the zone the tests run in, adding days goes by the date's
        // own fields, so the result is always midnight on the right day.
        final DateTime d = ReviewScheduler.addDays(DateTime(2026, 3, 28), 2);
        expect(d, DateTime(2026, 3, 30));
        expect(d.hour, 0);
        expect(
          ReviewScheduler.addDays(DateTime(2026, 12, 31), 1),
          DateTime(2027, 1, 1),
        );
      },
    );
  });

  group('the three places', () {
    test('new for a week, recent until a month, kept after', () {
      final ReviewCard c = started();
      expect(scheduler.tierOf(c, monday), ReviewTier.sabaq);
      expect(
        scheduler.tierOf(c, monday.add(const Duration(days: 6))),
        ReviewTier.sabaq,
      );
      expect(
        scheduler.tierOf(c, monday.add(const Duration(days: 7))),
        ReviewTier.sabqi,
      );
      expect(
        scheduler.tierOf(c, monday.add(const Duration(days: 29))),
        ReviewTier.sabqi,
      );
      expect(
        scheduler.tierOf(c, monday.add(const Duration(days: 30))),
        ReviewTier.manzil,
      );
    });
  });

  group('what is due', () {
    test('due on its day, and every day after until reviewed', () {
      final ReviewCard c = started();
      expect(scheduler.isDue(c, monday), isFalse);
      expect(scheduler.isDue(c, DateTime(2026, 10, 20, 0, 1)), isTrue);
      expect(scheduler.isDue(c, DateTime(2026, 11, 2)), isTrue);
    });

    test('new first, then recent, then kept; the longest waiting first in '
        'each; then in mushaf order', () {
      final DateTime now = DateTime(2026, 12, 1);
      ReviewCard card(AyahRef from, DateTime created, DateTime due) =>
          ReviewCard(from: from, to: from, step: 0, due: due, created: created);
      final ReviewCard oldLate = card(
        const AyahRef(2, 1),
        DateTime(2026, 1, 1),
        DateTime(2026, 11, 1),
      );
      final ReviewCard oldToday = card(
        const AyahRef(1, 1),
        DateTime(2026, 1, 1),
        DateTime(2026, 12, 1),
      );
      final ReviewCard recent = card(
        const AyahRef(3, 1),
        DateTime(2026, 11, 20),
        DateTime(2026, 12, 1),
      );
      final ReviewCard fresh = card(
        const AyahRef(4, 1),
        DateTime(2026, 11, 29),
        DateTime(2026, 11, 30),
      );
      final ReviewCard notYet = card(
        const AyahRef(5, 1),
        DateTime(2026, 11, 29),
        DateTime(2026, 12, 2),
      );
      expect(
        scheduler
            .dueToday(<ReviewCard>[
              oldToday,
              notYet,
              recent,
              oldLate,
              fresh,
            ], now)
            .map((ReviewCard c) => c.from.surah),
        <int>[4, 3, 2, 1],
      );
    });
  });

  group('the card in storage', () {
    test('round-trips', () {
      final ReviewCard c = scheduler.grade(started(), Grade.shaky, monday);
      expect(ReviewCard.fromMap(c.toMap()), c);
    });

    test('anything malformed reads as no card, never as an error', () {
      final Map<String, dynamic> good = started().toMap();
      for (final MapEntry<String, Object?> broken
          in <MapEntry<String, Object?>>[
            const MapEntry<String, Object?>('from', <int>[67]),
            const MapEntry<String, Object?>('to', 'x'),
            const MapEntry<String, Object?>('step', -1),
            const MapEntry<String, Object?>('due', '2026-13-01'),
            const MapEntry<String, Object?>('created', null),
            const MapEntry<String, Object?>('from', <int>[68, 1]),
          ]) {
        expect(
          ReviewCard.fromMap(<String, dynamic>{
            ...good,
            broken.key: broken.value,
          }),
          isNull,
          reason: '${broken.key}: ${broken.value}',
        );
      }
      expect(ReviewCard.fromMap('nonsense'), isNull);
    });

    test('an unknown grade reads as none, keeping the card', () {
      final ReviewCard? c = ReviewCard.fromMap(<String, dynamic>{
        ...started().toMap(),
        'lastGrade': 'excellent',
      });
      expect(c, isNotNull);
      expect(c!.lastGrade, isNull);
    });

    test('one card per exact range', () {
      expect(started().id, '67:1-67:5');
    });
  });
}
