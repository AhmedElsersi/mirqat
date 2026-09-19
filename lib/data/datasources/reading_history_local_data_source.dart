import 'package:hive_ce/hive.dart';

import '../../core/constants/app_constants.dart';
import '../../core/error/exceptions.dart';
import '../models/reading_position.dart';

/// Where the reader has been, kept on the device and nowhere else
/// (CLAUDE.md A.2 rule 3): plain maps in a `hive_ce` box, no generated
/// adapter, so no `build_runner` (A.4).
abstract class ReadingHistoryLocalDataSource {
  Future<void> open();

  /// Newest first.
  Future<List<ReadingPosition>> read();

  Future<void> write(List<ReadingPosition> positions);
}

class ReadingHistoryLocalDataSourceImpl
    implements ReadingHistoryLocalDataSource {
  ReadingHistoryLocalDataSourceImpl({String? boxName})
    : _boxName = boxName ?? AppConstants.readingHistoryBoxName;

  static const String _key = 'positions';

  final String _boxName;
  Box<List<dynamic>>? _box;

  @override
  Future<void> open() async {
    if (_box?.isOpen ?? false) return;
    try {
      _box = await Hive.openBox<List<dynamic>>(_boxName);
    } catch (e) {
      throw StorageException('Could not open the "$_boxName" box: $e');
    }
  }

  Box<List<dynamic>> get _requireBox {
    final Box<List<dynamic>>? box = _box;
    if (box == null || !box.isOpen) {
      throw const StorageException(
        'Reading history was used before open() was called.',
      );
    }
    return box;
  }

  @override
  Future<List<ReadingPosition>> read() async {
    final List<dynamic> stored = _requireBox.get(_key) ?? const <dynamic>[];
    return <ReadingPosition>[
      for (final Object? entry in stored)
        // An entry this build cannot read is dropped, not fatal: losing one
        // line of history is nothing next to refusing to open the app.
        if (entry is Map) ?_tryParse(entry),
    ];
  }

  static ReadingPosition? _tryParse(Map<dynamic, dynamic> map) {
    try {
      return ReadingPosition.fromMap(map);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(List<ReadingPosition> positions) => _requireBox.put(
    _key,
    <Map<String, Object>>[for (final ReadingPosition p in positions) p.toMap()],
  );
}
