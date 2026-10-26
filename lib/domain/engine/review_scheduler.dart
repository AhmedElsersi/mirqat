import '../entities/ayah_ref.dart';
import '../entities/review_card.dart';

/// When a memorized range comes back for review, and which of the three
/// places it belongs to. Pure Dart: the clock is handed in.
///
/// The ladder is expanding intervals — the spacing that the research on
/// retrieval practice favours, and what the strongest memorization apps
/// use. A solid review climbs a rung; a shaky one stays on its rung; a
/// forgotten one starts again from the bottom, due tomorrow.
class ReviewScheduler {
  const ReviewScheduler({
    this.ladder = defaultLadder,
    this.sabaqDays = 7,
    this.sabqiDays = 30,
  });

  /// Days between reviews, rung by rung.
  static const List<int> defaultLadder = <int>[1, 3, 7, 14, 30, 90];

  final List<int> ladder;

  /// A range younger than this many days is the new portion.
  final int sabaqDays;

  /// Younger than this, and not new, it is recent; older, it is kept.
  final int sabqiDays;

  /// The local calendar day [moment] falls on.
  static DateTime dayOf(DateTime moment) =>
      DateTime(moment.year, moment.month, moment.day);

  /// [days] calendar days after [day]. Built from the date's own fields, not
  /// by adding hours, so a change to or from daylight saving cannot land it
  /// on the wrong day.
  static DateTime addDays(DateTime day, int days) =>
      DateTime(day.year, day.month, day.day + days);

  /// Calendar days from [from] to [to]. Counted on the dates themselves, in
  /// UTC, because across a daylight-saving change local midnights are 23 or
  /// 25 hours apart and `difference().inDays` comes out a day short.
  static int daysBetween(DateTime from, DateTime to) => DateTime.utc(
    to.year,
    to.month,
    to.day,
  ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

  int _clampStep(int step) => step.clamp(0, ladder.length - 1);

  /// The first grade of a range starts its card on the bottom rung, due
  /// tomorrow, whatever the grade: a passage just learned is reviewed the
  /// next day either way.
  ReviewCard start({
    required AyahRef from,
    required AyahRef to,
    required Grade grade,
    required DateTime now,
  }) {
    final DateTime today = dayOf(now);
    return ReviewCard(
      from: from,
      to: to,
      step: 0,
      due: addDays(today, ladder.first),
      created: today,
      lastReviewed: now,
      lastGrade: grade,
    );
  }

  /// [card] after a review graded [grade] at [now].
  ReviewCard grade(ReviewCard card, Grade grade, DateTime now) {
    final int step = switch (grade) {
      Grade.solid => _clampStep(card.step + 1),
      Grade.shaky => _clampStep(card.step),
      Grade.forgot => 0,
    };
    return card.copyWith(
      step: step,
      due: addDays(dayOf(now), ladder[step]),
      lastReviewed: now,
      lastGrade: grade,
    );
  }

  /// Which of the three places [card] belongs to, by its age at [now].
  ReviewTier tierOf(ReviewCard card, DateTime now) {
    final int age = daysBetween(card.created, now);
    if (age < sabaqDays) return ReviewTier.sabaq;
    if (age < sabqiDays) return ReviewTier.sabqi;
    return ReviewTier.manzil;
  }

  /// Whether [card] is due on the day [now] falls on — or was due before and
  /// has waited.
  bool isDue(ReviewCard card, DateTime now) =>
      !dayOf(card.due).isAfter(dayOf(now));

  /// The cards due by today, new portions first, then recent, then kept;
  /// inside a tier the longest-waiting first, then in mushaf order.
  List<ReviewCard> dueToday(Iterable<ReviewCard> cards, DateTime now) {
    final List<ReviewCard> due = <ReviewCard>[
      for (final ReviewCard c in cards)
        if (isDue(c, now)) c,
    ];
    due.sort((ReviewCard a, ReviewCard b) {
      final int byTier = tierOf(a, now).index - tierOf(b, now).index;
      if (byTier != 0) return byTier;
      final int byDue = a.due.compareTo(b.due);
      if (byDue != 0) return byDue;
      return a.from.compareTo(b.from);
    });
    return due;
  }
}
