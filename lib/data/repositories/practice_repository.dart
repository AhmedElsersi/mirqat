import 'package:dartz/dartz.dart';

import '../../core/error/exceptions.dart';
import '../../core/error/failures.dart';
import '../../domain/entities/practice_stats.dart';
import '../datasources/practice_local_data_source.dart';

abstract class PracticeRepository {
  Future<Either<Failure, Unit>> add(DateTime day, PracticeDay practice);

  Future<Either<Failure, Map<DateTime, PracticeDay>>> all();

  /// Puts exactly [practice] for [day] — restoring a backup.
  Future<Either<Failure, Unit>> set(DateTime day, PracticeDay practice);
}

class PracticeRepositoryImpl implements PracticeRepository {
  const PracticeRepositoryImpl(this._local);

  final PracticeLocalDataSource _local;

  @override
  Future<Either<Failure, Unit>> add(DateTime day, PracticeDay practice) =>
      _guard(() async {
        await _local.add(day, practice);
        return unit;
      });

  @override
  Future<Either<Failure, Unit>> set(DateTime day, PracticeDay practice) =>
      _guard(() async {
        await _local.set(day, practice);
        return unit;
      });

  @override
  Future<Either<Failure, Map<DateTime, PracticeDay>>> all() =>
      _guard(_local.all);

  Future<Either<Failure, T>> _guard<T>(Future<T> Function() body) async {
    try {
      return Right<Failure, T>(await body());
    } on AppException catch (e) {
      return Left<Failure, T>(failureFromException(e));
    }
  }
}
