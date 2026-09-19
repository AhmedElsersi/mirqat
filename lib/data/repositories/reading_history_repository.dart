import 'package:dartz/dartz.dart';

import '../../core/error/exceptions.dart';
import '../../core/error/failures.dart';
import '../datasources/reading_history_local_data_source.dart';
import '../models/reading_position.dart';

/// "Open where I left off", and the list of where that has been.
abstract class ReadingHistoryRepository {
  /// Newest first, at most [ReadingHistoryRepositoryImpl.limit] long.
  Future<Either<Failure, List<ReadingPosition>>> history();

  /// The most recent position, or null on a fresh install.
  Future<Either<Failure, ReadingPosition?>> last();

  /// Notes that the reader is at [position].
  ///
  /// One *visit* is one entry. While a reading screen stays open it passes
  /// [sameVisit] and the top entry follows the reader from page to page;
  /// otherwise reading twenty pages in a sitting would push everything else
  /// out of a twenty-entry history. A new visit goes on top — unless it opens
  /// on the very place the last one ended, which is a continuation, not a
  /// second entry — and the list is cut to its limit from the old end.
  Future<Either<Failure, List<ReadingPosition>>> record(
    ReadingPosition position, {
    bool sameVisit = false,
  });

  Future<Either<Failure, Unit>> clear();
}

class ReadingHistoryRepositoryImpl implements ReadingHistoryRepository {
  ReadingHistoryRepositoryImpl(this._local);

  /// How many places are remembered.
  static const int limit = 20;

  final ReadingHistoryLocalDataSource _local;

  @override
  Future<Either<Failure, List<ReadingPosition>>> history() =>
      _guard(_local.read);

  @override
  Future<Either<Failure, ReadingPosition?>> last() => _guard(() async {
    final List<ReadingPosition> all = await _local.read();
    return all.isEmpty ? null : all.first;
  });

  @override
  Future<Either<Failure, List<ReadingPosition>>> record(
    ReadingPosition position, {
    bool sameVisit = false,
  }) => _guard(() async {
    final List<ReadingPosition> all = await _local.read();
    final bool replaceTop =
        all.isNotEmpty && (sameVisit || all.first.samePlaceAs(position));
    final List<ReadingPosition> next = <ReadingPosition>[
      position,
      ...all.skip(replaceTop ? 1 : 0),
    ].take(limit).toList();
    await _local.write(next);
    return next;
  });

  @override
  Future<Either<Failure, Unit>> clear() => _guard(() async {
    await _local.write(const <ReadingPosition>[]);
    return unit;
  });

  Future<Either<Failure, T>> _guard<T>(Future<T> Function() body) async {
    try {
      return Right<Failure, T>(await body());
    } on AppException catch (e) {
      return Left<Failure, T>(failureFromException(e));
    }
  }
}
