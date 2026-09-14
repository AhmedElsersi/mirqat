import 'package:dartz/dartz.dart';

import '../../core/error/exceptions.dart';
import '../../core/error/failures.dart';
import '../datasources/progress_local_data_source.dart';
import '../models/memorization_progress.dart';

abstract class ProgressRepository {
  Future<Either<Failure, MemorizationProgress>> getAyah(
    int surahNumber,
    int ayahNumber,
  );

  Future<Either<Failure, List<MemorizationProgress>>> getSurah(
    int surahNumber,
    int ayahCount,
  );

  Future<Either<Failure, Unit>> setStatus(
    int surahNumber,
    int ayahNumber,
    MemorizationStatus status,
  );

  Future<Either<Failure, Unit>> recordRepeats(
    int surahNumber,
    int ayahNumber,
    int repeats, {
    DateTime? at,
  });

  Future<Either<Failure, Unit>> clearSurah(int surahNumber, int ayahCount);

  /// Emits whenever any progress record is written, by anyone.
  ///
  /// Deliberately `void` rather than the changed record: every listener here
  /// shows an aggregate (a count, a bar), so knowing *that* something changed
  /// is enough and carrying the record would invite listeners to patch their
  /// state from it instead of re-reading.
  Stream<void> get changes;
}

class ProgressRepositoryImpl implements ProgressRepository {
  const ProgressRepositoryImpl(this._local);

  final ProgressLocalDataSource _local;

  @override
  Future<Either<Failure, MemorizationProgress>> getAyah(
    int surahNumber,
    int ayahNumber,
  ) => _guard(() => _local.get(surahNumber, ayahNumber));

  @override
  Future<Either<Failure, List<MemorizationProgress>>> getSurah(
    int surahNumber,
    int ayahCount,
  ) => _guard(() => _local.getForSurah(surahNumber, ayahCount));

  @override
  Future<Either<Failure, Unit>> setStatus(
    int surahNumber,
    int ayahNumber,
    MemorizationStatus status,
  ) => _guardUnit(() => _local.setStatus(surahNumber, ayahNumber, status));

  @override
  Future<Either<Failure, Unit>> recordRepeats(
    int surahNumber,
    int ayahNumber,
    int repeats, {
    DateTime? at,
  }) => _guardUnit(
    () => _local.recordRepeats(surahNumber, ayahNumber, repeats, at: at),
  );

  @override
  Future<Either<Failure, Unit>> clearSurah(int surahNumber, int ayahCount) =>
      _guardUnit(() => _local.clearSurah(surahNumber, ayahCount));

  @override
  Stream<void> get changes => _local.watchChanges();

  Future<Either<Failure, T>> _guard<T>(Future<T> Function() body) async {
    try {
      return Right<Failure, T>(await body());
    } on AppException catch (e) {
      return Left<Failure, T>(failureFromException(e));
    }
  }

  Future<Either<Failure, Unit>> _guardUnit(Future<void> Function() body) =>
      _guard(() async {
        await body();
        return unit;
      });
}
