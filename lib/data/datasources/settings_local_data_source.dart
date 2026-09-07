import 'package:hive_ce/hive.dart';

import '../../core/constants/app_constants.dart';
import '../../core/error/exceptions.dart';
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

  @override
  Future<AppSettings> read() async {
    final Map<dynamic, dynamic>? stored = _requireBox.get(_key);
    if (stored == null) return const AppSettings();
    try {
      return AppSettings.fromMap(stored);
    } catch (e) {
      throw StorageException('Stored settings are malformed: $e');
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
