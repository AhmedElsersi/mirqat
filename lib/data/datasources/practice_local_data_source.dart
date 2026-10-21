import 'package:hive_ce/hive.dart';

import '../../core/constants/app_constants.dart';
import '../../core/error/exceptions.dart';
import '../../domain/entities/practice_stats.dart';

/// What was practised each day, kept on the device and nowhere else
/// (CLAUDE.md A.2 rule 3): a plain map per day in a `hive_ce` box, keyed
/// `yyyy-mm-dd` in local time.
abstract class PracticeLocalDataSource {
  Future<void> open();

  /// Adds [practice] to what [day] already holds.
  Future<void> add(DateTime day, PracticeDay practice);

  /// Puts exactly [practice] for [day], whatever was there — restoring a
  /// backup, never counting the same day twice.
  Future<void> set(DateTime day, PracticeDay practice);

  /// Every day recorded. A record that cannot be read is left out.
  Future<Map<DateTime, PracticeDay>> all();
}

class PracticeLocalDataSourceImpl implements PracticeLocalDataSource {
  PracticeLocalDataSourceImpl({String? boxName})
    : _boxName = boxName ?? AppConstants.practiceDaysBoxName;

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
        'The practice log was used before open() was called.',
      );
    }
    return box;
  }

  static String keyFor(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  static DateTime? dayOf(Object? key) {
    if (key is! String) return null;
    final List<String> p = key.split('-');
    if (p.length != 3) return null;
    final int? y = int.tryParse(p[0]);
    final int? m = int.tryParse(p[1]);
    final int? d = int.tryParse(p[2]);
    if (y == null || m == null || d == null || m < 1 || m > 12) return null;
    if (d < 1 || d > 31) return null;
    return DateTime(y, m, d);
  }

  @override
  Future<void> add(DateTime day, PracticeDay practice) async {
    final String key = keyFor(day);
    final PracticeDay before =
        PracticeDay.fromMap(_requireBox.get(key)) ?? const PracticeDay();
    try {
      await _requireBox.put(key, before.plus(practice).toMap());
    } catch (e) {
      throw StorageException('Could not record practice for $key: $e');
    }
  }

  @override
  Future<void> set(DateTime day, PracticeDay practice) async {
    try {
      await _requireBox.put(keyFor(day), practice.toMap());
    } catch (e) {
      throw StorageException(
        'Could not record practice for ${keyFor(day)}: $e',
      );
    }
  }

  @override
  Future<Map<DateTime, PracticeDay>> all() async {
    final Map<DateTime, PracticeDay> out = <DateTime, PracticeDay>{};
    for (final dynamic key in _requireBox.keys) {
      final DateTime? day = dayOf(key);
      final PracticeDay? practice = PracticeDay.fromMap(_requireBox.get(key));
      if (day != null && practice != null) out[day] = practice;
    }
    return out;
  }
}
