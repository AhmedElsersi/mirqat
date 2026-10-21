import 'package:equatable/equatable.dart';

import 'ayah_ref.dart';

/// One day's new portion: a run of consecutive ayahs.
class Portion extends Equatable {
  const Portion(this.from, this.to);

  final AyahRef from;
  final AyahRef to;

  @override
  List<Object?> get props => <Object?>[from, to];
}

/// "Memorize from here to there in so many days": the range cut into daily
/// portions once, when the plan is made, and the reader's place in them.
///
/// The portions are fixed at creation and stored, not recomputed: a plan is
/// a promise to oneself, and it must not reshuffle under the reader if the
/// way portions are cut is ever refined.
class HifzPlan extends Equatable {
  const HifzPlan({
    required this.from,
    required this.to,
    required this.days,
    required this.started,
    required this.portions,
    this.completed = 0,
  });

  final AyahRef from;
  final AyahRef to;

  /// How many days the reader gave themselves.
  final int days;

  /// The day the plan began, at local midnight.
  final DateTime started;

  final List<Portion> portions;

  /// How many portions are memorized — graded after a session over them.
  final int completed;

  bool get isFinished => completed >= portions.length;

  /// The next portion to memorize, or null once all are done.
  Portion? get current => isFinished ? null : portions[completed];

  HifzPlan copyWith({int? completed}) => HifzPlan(
    from: from,
    to: to,
    days: days,
    started: started,
    portions: portions,
    completed: completed ?? this.completed,
  );

  Map<String, dynamic> toMap() => <String, dynamic>{
    'from': <int>[from.surah, from.ayah],
    'to': <int>[to.surah, to.ayah],
    'days': days,
    'started': <int>[started.year, started.month, started.day],
    'portions': <List<int>>[
      for (final Portion p in portions)
        <int>[p.from.surah, p.from.ayah, p.to.surah, p.to.ayah],
    ],
    'completed': completed,
  };

  /// Null for anything that is not a plan this app wrote, or one that does
  /// not hold together — portions that do not run in order from [from] to
  /// [to]. A plan that cannot be trusted is dropped, never half-followed.
  static HifzPlan? fromMap(Object? raw) {
    if (raw is! Map) return null;
    AyahRef? ref(Object? v, [int at = 0]) {
      if (v is! List || v.length < at + 2) return null;
      final Object? s = v[at];
      final Object? a = v[at + 1];
      return s is int && a is int && s >= 1 && a >= 1 ? AyahRef(s, a) : null;
    }

    final AyahRef? from = ref(raw['from']);
    final AyahRef? to = ref(raw['to']);
    final Object? days = raw['days'];
    final Object? started = raw['started'];
    final Object? rawPortions = raw['portions'];
    final Object? completed = raw['completed'];
    if (from == null ||
        to == null ||
        days is! int ||
        days < 1 ||
        started is! List ||
        started.length != 3 ||
        !started.every((Object? x) => x is int) ||
        rawPortions is! List ||
        rawPortions.isEmpty ||
        completed is! int ||
        completed < 0) {
      return null;
    }
    final List<Portion> portions = <Portion>[];
    for (final Object? p in rawPortions) {
      final AyahRef? a = ref(p);
      final AyahRef? b = ref(p, 2);
      if (a == null || b == null || b < a) return null;
      portions.add(Portion(a, b));
    }
    if (portions.first.from != from || portions.last.to != to) return null;
    for (int i = 1; i < portions.length; i++) {
      if (!(portions[i].from > portions[i - 1].to)) return null;
    }
    final List<int> d = started.cast<int>();
    return HifzPlan(
      from: from,
      to: to,
      days: days,
      started: DateTime(d[0], d[1], d[2]),
      portions: List<Portion>.unmodifiable(portions),
      completed: completed > portions.length ? portions.length : completed,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    from,
    to,
    days,
    started,
    portions,
    completed,
  ];
}
