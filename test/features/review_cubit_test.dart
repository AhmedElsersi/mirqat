import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/state/load_status.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:mirqat/domain/entities/ayah_ref.dart';
import 'package:mirqat/domain/entities/review_card.dart';
import 'package:mirqat/domain/entities/session_config.dart';
import 'package:mirqat/features/review/cubit/review_cubit.dart';
import 'package:mirqat/features/session/session_request.dart';

import '../fake_review_repository.dart';
import '../quran_db_fixtures.dart';

/// Surah fixtures, three ayahs each.
const Surah surah2 = Surah(
  number: 2,
  nameAr: 'ب',
  nameEn: 'B',
  ayahCount: 3,
  revelationPlace: RevelationPlace.madinah,
  bismillahMode: BismillahMode.separatePreamble,
);

void main() {
  late FakeReviewRepository reviews;
  final DateTime today = DateTime(2026, 12, 1, 10);

  setUp(() => reviews = FakeReviewRepository());

  ReviewCard card(
    AyahRef from,
    AyahRef to, {
    required DateTime created,
    required DateTime due,
  }) => ReviewCard(from: from, to: to, step: 0, due: due, created: created);

  Future<ReviewCubit> open() async {
    final ReviewCubit cubit = ReviewCubit(
      quranRepository: fixtureRepository(),
      reviewRepository: reviews,
      clock: () => today,
    );
    addTearDown(cubit.close);
    await cubit.load();
    return cubit;
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 5));

  test('due cards first, new before recent before kept; then the rest by '
      'the day they fall due', () async {
    await reviews.save(
      card(
        const AyahRef(1, 1),
        const AyahRef(1, 3),
        created: DateTime(2026, 1, 1),
        due: DateTime(2026, 12, 1),
      ),
    );
    await reviews.save(
      card(
        const AyahRef(2, 1),
        const AyahRef(2, 2),
        created: DateTime(2026, 11, 29),
        due: DateTime(2026, 11, 30),
      ),
    );
    await reviews.save(
      card(
        const AyahRef(3, 1),
        const AyahRef(3, 1),
        created: DateTime(2026, 11, 29),
        due: DateTime(2026, 12, 5),
      ),
    );
    await reviews.save(
      card(
        const AyahRef(2, 3),
        const AyahRef(2, 3),
        created: DateTime(2026, 11, 29),
        due: DateTime(2026, 12, 2),
      ),
    );
    final ReviewCubit cubit = await open();

    expect(cubit.state.status, LoadStatus.ready);
    expect(cubit.state.items.map((ReviewItem i) => i.card.id), <String>[
      '2:1-2:2',
      '1:1-1:3',
      '2:3-2:3',
      '3:1-3:1',
    ]);
    expect(cubit.state.dueToday.map((ReviewItem i) => i.tier), <ReviewTier>[
      ReviewTier.sabaq,
      ReviewTier.manzil,
    ]);
  });

  test('a card whose range the catalog does not hold is not shown', () async {
    await reviews.save(
      card(
        const AyahRef(1, 1),
        const AyahRef(1, 40),
        created: DateTime(2026, 11, 1),
        due: DateTime(2026, 11, 1),
      ),
    );
    await reviews.save(
      card(
        const AyahRef(150, 1),
        const AyahRef(150, 2),
        created: DateTime(2026, 11, 1),
        due: DateTime(2026, 11, 1),
      ),
    );
    final ReviewCubit cubit = await open();
    expect(cubit.state.items, isEmpty);
  });

  test('a card graded elsewhere is taken up without being asked', () async {
    final ReviewCubit cubit = await open();
    expect(cubit.state.items, isEmpty);
    await reviews.save(
      card(
        const AyahRef(1, 1),
        const AyahRef(1, 2),
        created: DateTime(2026, 11, 30),
        due: DateTime(2026, 12, 1),
      ),
    );
    await settle();
    expect(cubit.state.dueToday, hasLength(1));
  });

  test('forgetting a card takes it off the list', () async {
    await reviews.save(
      card(
        const AyahRef(1, 1),
        const AyahRef(1, 2),
        created: DateTime(2026, 11, 30),
        due: DateTime(2026, 12, 1),
      ),
    );
    final ReviewCubit cubit = await open();
    await cubit.delete(cubit.state.items.single);
    await settle();
    expect(cubit.state.items, isEmpty);
  });

  test('a review opens its range, started, lighter the older it is', () {
    final SessionRequest request = ReviewItem(
      card: card(
        const AyahRef(2, 1),
        const AyahRef(2, 3),
        created: DateTime(2026, 1, 1),
        due: DateTime(2026, 12, 1),
      ),
      tier: ReviewTier.manzil,
      fromSurah: surah2,
      toSurah: surah2,
      due: true,
    ).request;
    expect(request.from, const AyahRef(2, 1));
    expect(request.to, const AyahRef(2, 3));
    expect(request.autostart, isTrue);
    expect(request.preset.connectMode, ConnectMode.continuous);
    expect(request.preset.chainRecall, isTrue);

    expect(ReviewItem.presetFor(ReviewTier.sabaq), const SessionPreset());
    expect(ReviewItem.presetFor(ReviewTier.sabqi).recallRounds, 1);
  });
}
