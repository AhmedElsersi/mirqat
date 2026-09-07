import 'package:dartz/dartz.dart';

import '../../core/error/exceptions.dart';
import '../../core/error/failures.dart';
import '../datasources/settings_local_data_source.dart';
import '../models/app_settings.dart';

abstract class SettingsRepository {
  Future<Either<Failure, AppSettings>> read();

  Future<Either<Failure, AppSettings>> save(AppSettings settings);
}

class SettingsRepositoryImpl implements SettingsRepository {
  const SettingsRepositoryImpl(this._local);

  final SettingsLocalDataSource _local;

  @override
  Future<Either<Failure, AppSettings>> read() => _guard(_local.read);

  @override
  Future<Either<Failure, AppSettings>> save(AppSettings settings) =>
      _guard(() async {
        await _local.write(settings);
        return settings;
      });

  Future<Either<Failure, T>> _guard<T>(Future<T> Function() body) async {
    try {
      return Right<Failure, T>(await body());
    } on AppException catch (e) {
      return Left<Failure, T>(failureFromException(e));
    }
  }
}
