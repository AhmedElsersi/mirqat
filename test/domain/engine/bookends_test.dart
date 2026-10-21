import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/data/models/app_settings.dart';
import 'package:mirqat/domain/engine/bookends.dart';
import 'package:mirqat/domain/entities/ayah_ref.dart';
import 'package:mirqat/domain/entities/review_card.dart';

ReviewCard card(
  int surah,
  int ayah, {
  required DateTime created,
  DateTime? reviewed,
}) => ReviewCard(
  from: AyahRef(surah, ayah),
  to: AyahRef(surah, ayah + 4),
  step: 0,
  due: DateTime(created.year, created.month, created.day + 1),
  created: DateTime(created.year, created.month, created.day),
  lastReviewed: reviewed ?? created,
);

void main() {
  const Bookends bookends = Bookends();
  final DateTime today = DateTime(2026, 11, 10);
  final DateTime yesterday = DateTime(2026, 11, 9);
  final ReviewCard learnedToday = card(
    2,
    1,
    created: today.add(const Duration(hours: 15)),
  );
  final ReviewCard learnedYesterday = card(
    1,
    1,
    created: yesterday.add(const Duration(hours: 16)),
  );
  final List<ReviewCard> cards = <ReviewCard>[learnedToday, learnedYesterday];

  group('at night', () {
    test('suggests the portion first memorized today', () {
      final Bookend? b = bookends.suggest(
        cards,
        today.add(const Duration(hours: 21)),
      );
      expect(b?.time, BookendTime.night);
      expect(b?.card, learnedToday);
    });

    test('after midnight it is still tonight: the day just gone', () {
      final Bookend? b = bookends.suggest(
        cards,
        today.add(const Duration(hours: 25)), // 01:00 the next day
      );
      expect(b?.time, BookendTime.night);
      expect(b?.card, learnedToday);
    });

    test('nothing new memorized today: nothing suggested', () {
      expect(
        bookends.suggest(<ReviewCard>[
          learnedYesterday,
        ], today.add(const Duration(hours: 21))),
        isNull,
      );
    });
  });

  group('in the morning', () {
    test('suggests the portion first memorized yesterday', () {
      final Bookend? b = bookends.suggest(
        cards,
        today.add(const Duration(hours: 7)),
      );
      expect(b?.time, BookendTime.morning);
      expect(b?.card, learnedYesterday);
    });

    test('not once that portion has been reviewed this morning', () {
      final ReviewCard done = card(
        1,
        1,
        created: yesterday,
        reviewed: today.add(const Duration(hours: 6)),
      );
      expect(
        bookends.suggest(<ReviewCard>[
          done,
        ], today.add(const Duration(hours: 8))),
        isNull,
      );
    });
  });

  test('between the two, nothing: no window is ever "missed"', () {
    for (final int hour in <int>[3, 12, 15, 18]) {
      expect(
        bookends.suggest(cards, today.add(Duration(hours: hour))),
        isNull,
        reason: '$hour:00',
      );
    }
  });

  test('a suggestion taken is not made again; the next one still is', () {
    final DateTime night = today.add(const Duration(hours: 22));
    final Bookend first = bookends.suggest(cards, night)!;
    expect(bookends.suggest(cards, night, taken: first.key), isNull);
    // The morning after is another suggestion, with its own key.
    final Bookend? morning = bookends.suggest(
      cards,
      today.add(const Duration(hours: 31)), // 07:00 the next day
      taken: first.key,
    );
    expect(morning?.time, BookendTime.morning);
    expect(morning?.card, learnedToday);
    expect(morning?.key, isNot(first.key));
  });

  test('of two portions memorized the same day, the one the reader was on '
      'last', () {
    final ReviewCard earlier = card(
      3,
      1,
      created: today,
      reviewed: today.add(const Duration(hours: 9)),
    );
    final ReviewCard later = card(
      3,
      20,
      created: today,
      reviewed: today.add(const Duration(hours: 17)),
    );
    expect(
      bookends.suggest(<ReviewCard>[
        later,
        earlier,
      ], today.add(const Duration(hours: 20)))?.card,
      later,
    );
  });

  group('the setting', () {
    test('is off for a reader who never chose it, and kept when chosen', () {
      expect(AppSettings.fromMap(const <String, dynamic>{}).bookends, isFalse);
      final AppSettings on = const AppSettings().copyWith(
        bookends: true,
        bookendTaken: 'night:2:1-2:5:2026-11-10',
      );
      final AppSettings back = AppSettings.fromMap(on.toMap());
      expect(back.bookends, isTrue);
      expect(back.bookendTaken, 'night:2:1-2:5:2026-11-10');
    });

    test('a stored value of the wrong type reads as nothing taken', () {
      expect(
        AppSettings.fromMap(const <String, dynamic>{
          'bookends': 'yes',
          'bookendTaken': 7,
        }).bookendTaken,
        isNull,
      );
    });
  });
}
