import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:mirqat/core/error/failures.dart';
import 'package:mirqat/data/repositories/review_repository.dart';
import 'package:mirqat/domain/entities/review_card.dart';

/// The review ladder in memory, with the change stream the real box gives.
class FakeReviewRepository implements ReviewRepository {
  final Map<String, ReviewCard> cards = <String, ReviewCard>{};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  Future<Either<Failure, List<ReviewCard>>> all() async =>
      Right<Failure, List<ReviewCard>>(cards.values.toList());

  @override
  Future<Either<Failure, ReviewCard?>> get(String id) async =>
      Right<Failure, ReviewCard?>(cards[id]);

  @override
  Future<Either<Failure, Unit>> save(ReviewCard card) async {
    cards[card.id] = card;
    _changes.add(null);
    return const Right<Failure, Unit>(unit);
  }

  @override
  Future<Either<Failure, Unit>> delete(String id) async {
    cards.remove(id);
    _changes.add(null);
    return const Right<Failure, Unit>(unit);
  }

  @override
  Stream<void> get changes => _changes.stream;
}
