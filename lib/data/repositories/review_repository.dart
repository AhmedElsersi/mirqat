import 'package:dartz/dartz.dart';

import '../../core/error/exceptions.dart';
import '../../core/error/failures.dart';
import '../../domain/entities/review_card.dart';
import '../datasources/review_local_data_source.dart';

abstract class ReviewRepository {
  Future<Either<Failure, List<ReviewCard>>> all();

  /// The card for exactly this range, or null when it has never been graded.
  Future<Either<Failure, ReviewCard?>> get(String id);

  Future<Either<Failure, Unit>> save(ReviewCard card);

  Future<Either<Failure, Unit>> delete(String id);

  /// Emits whenever any card changes, by anyone.
  Stream<void> get changes;
}

class ReviewRepositoryImpl implements ReviewRepository {
  const ReviewRepositoryImpl(this._local);

  final ReviewLocalDataSource _local;

  @override
  Future<Either<Failure, List<ReviewCard>>> all() => _guard(_local.all);

  @override
  Future<Either<Failure, ReviewCard?>> get(String id) =>
      _guard(() => _local.get(id));

  @override
  Future<Either<Failure, Unit>> save(ReviewCard card) => _guard(() async {
    await _local.save(card);
    return unit;
  });

  @override
  Future<Either<Failure, Unit>> delete(String id) => _guard(() async {
    await _local.delete(id);
    return unit;
  });

  @override
  Stream<void> get changes => _local.watchChanges();

  Future<Either<Failure, T>> _guard<T>(Future<T> Function() body) async {
    try {
      return Right<Failure, T>(await body());
    } on AppException catch (e) {
      return Left<Failure, T>(failureFromException(e));
    }
  }
}
