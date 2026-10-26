import 'package:equatable/equatable.dart';

import 'ayah_ref.dart';

/// How a review went, in the reader's own words.
enum Grade {
  /// Recited without a slip.
  solid('solid'),

  /// Recited, with hesitation or a slip caught.
  shaky('shaky'),

  /// Not held.
  forgot('forgot');

  const Grade(this.storageValue);

  final String storageValue;

  static Grade? fromStorage(Object? value) {
    for (final Grade g in Grade.values) {
      if (g.storageValue == value) return g;
    }
    return null;
  }
}

/// The three places a hafiz keeps, as the madrasa names them.
enum ReviewTier {
  /// Sabaq — the new portion, memorized this week.
  sabaq,

  /// Sabqi — the recent portions, of the last few weeks.
  sabqi,

  /// Manzil — everything older, kept by a rotating revision.
  manzil,
}

/// One memorized range and where it stands on the review ladder.
///
/// A range, not an ayah: a hafiz revises passages, and a passage is what a
/// session recites. Dates are calendar days in local time — a review is due
/// on a day, not after a count of hours, so a clock moved or a time zone
/// crossed cannot make it due twice or never.
class ReviewCard extends Equatable {
  const ReviewCard({
    required this.from,
    required this.to,
    required this.step,
    required this.due,
    required this.created,
    this.lastReviewed,
    this.lastGrade,
  });

  final AyahRef from;
  final AyahRef to;

  /// Index into the scheduler's ladder of the interval that set [due].
  final int step;

  /// The day the range is next due, at midnight local time.
  final DateTime due;

  /// The day the range was first graded — when it was memorized, as far as
  /// the app knows. Its age decides its tier.
  final DateTime created;

  final DateTime? lastReviewed;
  final Grade? lastGrade;

  /// One card per exact range: a range graded again is the same card.
  String get id => idFor(from, to);

  static String idFor(AyahRef from, AyahRef to) =>
      '${from.surah}:${from.ayah}-${to.surah}:${to.ayah}';

  ReviewCard copyWith({
    int? step,
    DateTime? due,
    DateTime? lastReviewed,
    Grade? lastGrade,
  }) => ReviewCard(
    from: from,
    to: to,
    step: step ?? this.step,
    due: due ?? this.due,
    created: created,
    lastReviewed: lastReviewed ?? this.lastReviewed,
    lastGrade: lastGrade ?? this.lastGrade,
  );

  Map<String, dynamic> toMap() => <String, dynamic>{
    'from': <int>[from.surah, from.ayah],
    'to': <int>[to.surah, to.ayah],
    'step': step,
    'due': _day(due),
    'created': _day(created),
    'lastReviewed': lastReviewed?.toIso8601String(),
    'lastGrade': lastGrade?.storageValue,
  };

  /// Null for anything that is not a card this app wrote: a malformed record
  /// costs that record, never the list it is in.
  static ReviewCard? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final AyahRef? from = _ref(raw['from']);
    final AyahRef? to = _ref(raw['to']);
    final Object? step = raw['step'];
    final DateTime? due = _parseDay(raw['due']);
    final DateTime? created = _parseDay(raw['created']);
    if (from == null ||
        to == null ||
        to < from ||
        step is! int ||
        step < 0 ||
        due == null ||
        created == null) {
      return null;
    }
    final Object? reviewed = raw['lastReviewed'];
    return ReviewCard(
      from: from,
      to: to,
      step: step,
      due: due,
      created: created,
      lastReviewed: reviewed is String ? DateTime.tryParse(reviewed) : null,
      lastGrade: Grade.fromStorage(raw['lastGrade']),
    );
  }

  static AyahRef? _ref(Object? raw) {
    if (raw is! List || raw.length != 2) return null;
    final Object? s = raw[0];
    final Object? a = raw[1];
    if (s is! int || a is! int || s < 1 || a < 1) return null;
    return AyahRef(s, a);
  }

  /// `yyyy-mm-dd`: a day, with no time and no zone to drift.
  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime? _parseDay(Object? raw) {
    if (raw is! String) return null;
    final List<String> parts = raw.split('-');
    if (parts.length != 3) return null;
    final int? y = int.tryParse(parts[0]);
    final int? m = int.tryParse(parts[1]);
    final int? d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    return DateTime(y, m, d);
  }

  @override
  List<Object?> get props => <Object?>[
    from,
    to,
    step,
    due,
    created,
    lastReviewed,
    lastGrade,
  ];
}
