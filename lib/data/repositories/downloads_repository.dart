import 'package:dartz/dartz.dart';

import '../../core/error/exceptions.dart';
import '../../core/error/failures.dart';
import '../datasources/downloads_local_data_source.dart';
import '../models/audio_pack.dart';

abstract class DownloadsRepository {
  Future<Either<Failure, List<InstalledPack>>> installed();

  Future<Either<Failure, Option<InstalledPack>>> installedPack(
    String reciterId,
    int surahNumber,
  );

  Future<Either<Failure, Unit>> record(InstalledPack pack);

  Future<Either<Failure, Unit>> forget(String reciterId, int surahNumber);

  Future<Either<Failure, Unit>> forgetReciter(String reciterId);

  /// Marks [reciterId]'s downloads stale where they were fetched at a version
  /// the manifest no longer publishes; answers how many.
  Future<Either<Failure, int>> markStale(
    String reciterId,
    String manifestVersion,
  );

  /// Emits whenever an install is recorded or forgotten, by anyone.
  Stream<void> get changes;
}

class DownloadsRepositoryImpl implements DownloadsRepository {
  const DownloadsRepositoryImpl(this._local);

  final DownloadsLocalDataSource _local;

  @override
  Future<Either<Failure, List<InstalledPack>>> installed() =>
      _guard(() => _local.list());

  @override
  Future<Either<Failure, Option<InstalledPack>>> installedPack(
    String reciterId,
    int surahNumber,
  ) => _guard(() async => optionOf(await _local.get(reciterId, surahNumber)));

  @override
  Future<Either<Failure, Unit>> record(InstalledPack pack) =>
      _guard(() async {
        await _local.record(pack);
        return unit;
      });

  @override
  Future<Either<Failure, Unit>> forget(String reciterId, int surahNumber) =>
      _guard(() async {
        await _local.remove(reciterId, surahNumber);
        return unit;
      });

  @override
  Future<Either<Failure, Unit>> forgetReciter(String reciterId) =>
      _guard(() async {
        await _local.removeReciter(reciterId);
        return unit;
      });

  @override
  Future<Either<Failure, int>> markStale(
    String reciterId,
    String manifestVersion,
  ) => _guard(() => _local.markReciterStale(reciterId, manifestVersion));

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
