import '../entities/review_card.dart';
import 'review_scheduler.dart';

/// Which end of the day a suggestion is for.
enum BookendTime {
  /// Last thing before sleep: today's new portion, heard once more.
  night,

  /// First thing the next day: last night's portion, recited back.
  morning,
}

/// One suggestion: the portion, and when it is for.
class Bookend {
  const Bookend({required this.time, required this.card, required this.day});

  final BookendTime time;
  final ReviewCard card;

  /// The day the portion was memorized — the day this night belongs to.
  final DateTime day;

  /// Names this one suggestion, so that once it is taken it is not made
  /// again: the same portion, the same end of the same night.
  String get key =>
      '${time.name}:${card.id}:${day.year}-${day.month}-${day.day}';
}

/// Sleep between two practice sessions roughly halves the practice needed
/// and improves retention months later (Mazza et al. 2016). So the day's new
/// portion is suggested again last thing at night, and once more the next
/// morning — the two ends of the night it is consolidated over.
///
/// Pure Dart: it reads the review cards, which already know which range was
/// first memorized on which day, and the clock. It never says a time was
/// missed: out of its windows it simply suggests nothing.
class Bookends {
  const Bookends({
    this.nightFrom = 19,
    this.nightUntil = 3,
    this.morningFrom = 4,
    this.morningUntil = 12,
  });

  /// The evening window, as hours of the local clock: from [nightFrom]
  /// through midnight until [nightUntil]. After midnight it is still
  /// "tonight" — the portion of the day just gone.
  final int nightFrom;
  final int nightUntil;

  /// The morning window, [morningFrom] until [morningUntil].
  final int morningFrom;
  final int morningUntil;

  /// The suggestion for [now], if there is one: none outside the two
  /// windows, none for a day nothing new was memorized, none once [taken]
  /// names it, and no morning one for a portion already reviewed today.
  Bookend? suggest(List<ReviewCard> cards, DateTime now, {String? taken}) {
    final BookendTime? time = _timeOf(now.hour);
    if (time == null) return null;
    // The day the night belongs to: before [nightUntil] it is yesterday's.
    final DateTime evening = ReviewScheduler.dayOf(
      now.hour < nightUntil ? ReviewScheduler.addDays(now, -1) : now,
    );
    final DateTime learned = time == BookendTime.night
        ? evening
        : ReviewScheduler.addDays(ReviewScheduler.dayOf(now), -1);

    // The portion first memorized that day; of several, the one reviewed
    // last — the one the reader was on most recently.
    ReviewCard? best;
    for (final ReviewCard c in cards) {
      if (ReviewScheduler.dayOf(c.created) != learned) continue;
      if (best == null || _later(c, best)) best = c;
    }
    if (best == null) return null;
    final DateTime? reviewed = best.lastReviewed;
    if (time == BookendTime.morning &&
        reviewed != null &&
        ReviewScheduler.dayOf(reviewed) == ReviewScheduler.dayOf(now)) {
      return null;
    }
    final Bookend bookend = Bookend(time: time, card: best, day: learned);
    return bookend.key == taken ? null : bookend;
  }

  BookendTime? _timeOf(int hour) {
    if (hour >= nightFrom || hour < nightUntil) return BookendTime.night;
    if (hour >= morningFrom && hour < morningUntil) return BookendTime.morning;
    return null;
  }

  static bool _later(ReviewCard a, ReviewCard b) {
    final DateTime? x = a.lastReviewed;
    final DateTime? y = b.lastReviewed;
    if (x != null && y != null && x != y) return x.isAfter(y);
    if ((x == null) != (y == null)) return x != null;
    // Same day, nothing to tell them apart: the later in the mushaf.
    return a.from.compareTo(b.from) > 0;
  }
}
