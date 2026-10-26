import 'dart:async';

import 'package:dartz/dartz.dart' hide State;
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failures.dart';
import '../../../core/state/load_status.dart';
import '../../../data/models/surah.dart';
import '../../../data/repositories/quran_repository.dart';
import '../../../data/repositories/review_repository.dart';
import '../../../domain/engine/review_scheduler.dart';
import '../../../domain/entities/ayah_ref.dart';
import '../../../domain/entities/review_card.dart';
import '../../session/session_request.dart';

/// One card, with what it takes to show it and to open it.
class ReviewItem extends Equatable {
  const ReviewItem({
    required this.card,
    required this.tier,
    required this.fromSurah,
    required this.toSurah,
    required this.due,
  });

  final ReviewCard card;
  final ReviewTier tier;
  final Surah fromSurah;
  final Surah toSurah;

  /// Due today, or waiting since an earlier day.
  final bool due;

  /// The session a review of this card opens: its range, the tier's preset,
  /// started at once.
  SessionRequest get request => SessionRequest(
    from: card.from,
    to: card.to,
    preset: presetFor(tier),
    autostart: true,
  );

  /// How lightly each place is revised. The new portion is drilled the
  /// reader's own way; a recent one is gone over twice with one recall; an
  /// old one is recited straight through once, then its links are tested.
  static SessionPreset presetFor(ReviewTier tier) => switch (tier) {
    ReviewTier.sabaq => const SessionPreset(),
    ReviewTier.sabqi => SessionPreset.recent,
    ReviewTier.manzil => SessionPreset.old,
  };

  @override
  List<Object?> get props => <Object?>[card, tier, fromSurah, toSurah, due];
}

class ReviewState extends Equatable {
  const ReviewState({
    this.status = LoadStatus.initial,
    this.items = const <ReviewItem>[],
    this.surahs = const <int, Surah>{},
    this.errorMessage,
  });

  final LoadStatus status;

  /// Every card: the due ones first — new, recent, kept — then the rest by
  /// the day they fall due.
  final List<ReviewItem> items;

  /// The catalog by number, to name ranges that are not cards.
  final Map<int, Surah> surahs;
  final String? errorMessage;

  List<ReviewItem> get dueToday => <ReviewItem>[
    for (final ReviewItem i in items)
      if (i.due) i,
  ];

  @override
  List<Object?> get props => <Object?>[status, items, surahs, errorMessage];
}

/// The review ladder as the reader sees it: what is due today, and every
/// range the app is keeping for them.
class ReviewCubit extends Cubit<ReviewState> {
  ReviewCubit({
    required QuranRepository quranRepository,
    required ReviewRepository reviewRepository,
    ReviewScheduler reviewScheduler = const ReviewScheduler(),
    this.clock = DateTime.now,
  }) : _quran = quranRepository,
       _reviews = reviewRepository,
       _scheduler = reviewScheduler,
       super(const ReviewState());

  final QuranRepository _quran;
  final ReviewRepository _reviews;
  final ReviewScheduler _scheduler;

  /// Today, as far as the ladder is concerned. A test hands in its own.
  final DateTime Function() clock;

  StreamSubscription<void>? _changes;

  Future<void> load() async {
    _changes ??= _reviews.changes.listen((_) => load());
    if (state.status == LoadStatus.initial) {
      emit(const ReviewState(status: LoadStatus.loading));
    }
    final Either<Failure, List<Surah>> surahs = await _quran.getSurahs();
    final Either<Failure, List<ReviewCard>> cards = await _reviews.all();
    if (isClosed) return;

    final String? failure = surahs.fold(
      (Failure f) => f.message,
      (_) => cards.fold((Failure f) => f.message, (_) => null),
    );
    if (failure != null) {
      emit(ReviewState(status: LoadStatus.failure, errorMessage: failure));
      return;
    }

    final Map<int, Surah> byNumber = <int, Surah>{
      for (final Surah s in surahs.getOrElse(() => const <Surah>[]))
        s.number: s,
    };
    final DateTime now = clock();
    final List<ReviewCard> all = cards.getOrElse(() => const <ReviewCard>[]);
    final List<ReviewCard> due = _scheduler.dueToday(all, now);
    final List<ReviewCard> later =
        <ReviewCard>[
          for (final ReviewCard c in all)
            if (!_scheduler.isDue(c, now)) c,
        ]..sort((ReviewCard a, ReviewCard b) {
          final int byDue = a.due.compareTo(b.due);
          return byDue != 0 ? byDue : a.from.compareTo(b.from);
        });

    emit(
      ReviewState(
        status: LoadStatus.ready,
        surahs: byNumber,
        items: <ReviewItem>[
          for (final ReviewCard c in <ReviewCard>[...due, ...later])
            ?_itemFor(c, byNumber, now),
        ],
      ),
    );
  }

  /// Null for a card whose range the catalog does not hold: there would be
  /// nothing to open.
  ReviewItem? _itemFor(ReviewCard card, Map<int, Surah> surahs, DateTime now) {
    final Surah? from = surahs[card.from.surah];
    final Surah? to = surahs[card.to.surah];
    if (from == null || to == null) return null;
    if (!_holds(from, card.from) || !_holds(to, card.to)) return null;
    return ReviewItem(
      card: card,
      tier: _scheduler.tierOf(card, now),
      fromSurah: from,
      toSurah: to,
      due: _scheduler.isDue(card, now),
    );
  }

  static bool _holds(Surah s, AyahRef ref) =>
      ref.ayah >= 1 && ref.ayah <= s.ayahCount;

  /// Stops keeping a range. Its progress stays; only the ladder forgets it.
  Future<void> delete(ReviewItem item) => _reviews.delete(item.card.id);

  @override
  Future<void> close() async {
    await _changes?.cancel();
    return super.close();
  }
}
