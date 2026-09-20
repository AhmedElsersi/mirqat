import 'dart:async';

import 'package:dartz/dartz.dart';

import '../../core/error/exceptions.dart';
import '../../core/error/failures.dart';
import '../datasources/settings_local_data_source.dart';
import '../models/app_settings.dart';

abstract class SettingsRepository {
  Future<Either<Failure, AppSettings>> read();

  Future<Either<Failure, AppSettings>> save(AppSettings settings);

  /// Every settings map that has been saved, as it is saved.
  ///
  /// The settings are one map with more than one writer — the settings
  /// screen, a session saving its values as defaults, the update prompt
  /// noting when it last spoke. Each holds a copy; without this, whoever
  /// saves next writes their stale copy over what the others changed.
  Stream<AppSettings> get changes;
}

class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl(this._local);

  final SettingsLocalDataSource _local;

  final StreamController<AppSettings> _changes =
      StreamController<AppSettings>.broadcast();

  @override
  Stream<AppSettings> get changes => _changes.stream;

  @override
  Future<Either<Failure, AppSettings>> read() => _guard(_local.read);

  @override
  Future<Either<Failure, AppSettings>> save(AppSettings settings) =>
      _guard(() async {
        await _local.write(settings);
        _changes.add(settings);
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
