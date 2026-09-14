import 'dart:developer' as developer;

import 'package:hive_ce/hive.dart';

import '../../core/constants/app_constants.dart';
import '../../core/error/exceptions.dart';
import '../../domain/entities/session_config.dart';
import '../models/app_settings.dart';

/// Settings persisted with `hive_ce`, as a single plain map under one key —
/// no generated adapter, so no `build_runner` (CLAUDE.md A.4).
abstract class SettingsLocalDataSource {
  Future<void> open();

  Future<AppSettings> read();

  Future<void> write(AppSettings settings);
}

class SettingsLocalDataSourceImpl implements SettingsLocalDataSource {
  SettingsLocalDataSourceImpl({String? boxName})
    : _boxName = boxName ?? AppConstants.settingsBoxName;

  static const String _key = 'app_settings';

  final String _boxName;
  Box<Map<dynamic, dynamic>>? _box;

  @override
  Future<void> open() async {
    if (_box?.isOpen ?? false) return;
    try {
      _box = await Hive.openBox<Map<dynamic, dynamic>>(_boxName);
    } catch (e) {
      throw StorageException('Could not open the "$_boxName" box: $e');
    }
  }

  Box<Map<dynamic, dynamic>> get _requireBox {
    final Box<Map<dynamic, dynamic>>? box = _box;
    if (box == null || !box.isOpen) {
      throw const StorageException(
        'Settings storage was used before open() was called.',
      );
    }
    return box;
  }

  /// Guards the migration log line: one entry per process, not one per read.
  bool _loggedConnectModeMigration = false;

  @override
  Future<AppSettings> read() async {
    final Map<dynamic, dynamic>? stored = _requireBox.get(_key);
    if (stored == null) return const AppSettings();

    final AppSettings settings;
    try {
      settings = AppSettings.fromMap(stored);
    } catch (e) {
      throw StorageException('Stored settings are malformed: $e');
    }

    await _migrateConnectMode(stored, settings);
    return settings;
  }

  /// Rewrites a persisted connect mode that no longer exists.
  ///
  /// A device upgrading from a build that had `pairwise` selected holds that
  /// string in the box. Reading it must neither crash nor quietly answer with
  /// an unrelated default, so [ConnectMode.decodeStored] reports *how* it was
  /// read and this rewrites the box when the answer differs from what is on
  /// disk. Without the rewrite the remap would be recomputed on every launch
  /// and the stale value would outlive the code that understood it.
  ///
  /// The mode is stored by `name`, never by index, so removing an enum case
  /// cannot shift the meaning of an unrelated stored value — `continuous`
  /// reads back as `continuous` no matter where it sits in the declaration.
  /// That is the whole reason this is a five-line remap and not an ordinal
  /// migration.
  Future<void> _migrateConnectMode(
    Map<dynamic, dynamic> stored,
    AppSettings settings,
  ) async {
    final StoredConnectMode decoded = ConnectMode.decodeStored(
      stored['defaultConnectMode'],
    );
    if (!decoded.needsRewrite) return;

    if (!_loggedConnectModeMigration) {
      _loggedConnectModeMigration = true;
      developer.log(
        'Settings migration: defaultConnectMode "${decoded.raw}" is '
        '${decoded.status == StoredConnectModeStatus.retired ? 'retired' : 'unreadable'}'
        '; rewritten as "${decoded.mode.name}".',
        name: 'settings',
      );
    }

    try {
      await write(settings);
    } on StorageException {
      // A failed rewrite is not worth failing the read over: the decode
      // already produced a usable mode, so the session is correct either way
      // and the migration simply retries on the next launch.
    }
  }

  @override
  Future<void> write(AppSettings settings) async {
    try {
      await _requireBox.put(_key, settings.toMap());
    } on StorageException {
      rethrow;
    } catch (e) {
      throw StorageException('Could not save settings: $e');
    }
  }
}
