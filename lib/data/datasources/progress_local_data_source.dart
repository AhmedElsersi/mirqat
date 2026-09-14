import 'package:hive_ce/hive.dart';

import '../../core/constants/app_constants.dart';
import '../../core/error/exceptions.dart';
import '../models/memorization_progress.dart';

/// Per-ayah memorization state, persisted with `hive_ce`.
///
/// Records are stored as plain maps keyed `<surah>:<ayah>`, which keeps the
/// project free of `build_runner` and `hive_ce_generator` — neither is on the
/// approved package list (CLAUDE.md A.4).
abstract class ProgressLocalDataSource {
  Future<void> open();

  Future<MemorizationProgress> get(int surahNumber, int ayahNumber);

  /// Progress for every ayah of a surah, 1..[ayahCount]. Ayahs never touched
  /// come back as [MemorizationStatus.notStarted] rather than being absent.
  Future<List<MemorizationProgress>> getForSurah(
    int surahNumber,
    int ayahCount,
  );

  Future<void> save(MemorizationProgress progress);

  Future<void> setStatus(
    int surahNumber,
    int ayahNumber,
    MemorizationStatus status,
  );

  /// Adds [repeats] to an ayah's running total and stamps the session time.
  /// An ayah that was [MemorizationStatus.notStarted] becomes
  /// [MemorizationStatus.inProgress]; one already marked memorized stays so.
  Future<void> recordRepeats(
    int surahNumber,
    int ayahNumber,
    int repeats, {
    DateTime? at,
  });

  Future<void> clearSurah(int surahNumber, int ayahCount);

  /// Fires once per record written, for screens that show a progress summary
  /// they did not write themselves.
  ///
  /// The home list is the case that matters: it is still mounted underneath
  /// the progress screen and the player, so it never rebuilds on its own when
  /// either of them marks an ayah.
  Stream<void> watchChanges();
}

class ProgressLocalDataSourceImpl implements ProgressLocalDataSource {
  ProgressLocalDataSourceImpl({String? boxName})
    : _boxName = boxName ?? AppConstants.progressBoxName;

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
        'Progress storage was used before open() was called.',
      );
    }
    return box;
  }

  @override
  Future<MemorizationProgress> get(int surahNumber, int ayahNumber) async {
    final Map<dynamic, dynamic>? stored = _requireBox.get(
      MemorizationProgress.keyFor(surahNumber, ayahNumber),
    );
    if (stored == null) {
      return MemorizationProgress(
        surahNumber: surahNumber,
        ayahNumber: ayahNumber,
      );
    }
    return _read(stored, surahNumber, ayahNumber);
  }

  @override
  Future<List<MemorizationProgress>> getForSurah(
    int surahNumber,
    int ayahCount,
  ) async {
    final List<MemorizationProgress> out = <MemorizationProgress>[];
    for (int ayah = 1; ayah <= ayahCount; ayah++) {
      out.add(await get(surahNumber, ayah));
    }
    return List<MemorizationProgress>.unmodifiable(out);
  }

  @override
  Future<void> save(MemorizationProgress progress) async {
    try {
      await _requireBox.put(progress.storageKey, progress.toMap());
    } on StorageException {
      rethrow;
    } catch (e) {
      throw StorageException(
        'Could not save progress for ${progress.storageKey}: $e',
      );
    }
  }

  @override
  Future<void> setStatus(
    int surahNumber,
    int ayahNumber,
    MemorizationStatus status,
  ) async {
    final MemorizationProgress current = await get(surahNumber, ayahNumber);
    await save(current.copyWith(status: status));
  }

  @override
  Future<void> recordRepeats(
    int surahNumber,
    int ayahNumber,
    int repeats, {
    DateTime? at,
  }) async {
    if (repeats < 0) {
      throw StorageException(
        'Cannot record $repeats repeats for $surahNumber:$ayahNumber — '
        'repeats must not be negative.',
      );
    }
    final MemorizationProgress current = await get(surahNumber, ayahNumber);
    await save(
      current.copyWith(
        status: current.status == MemorizationStatus.notStarted
            ? MemorizationStatus.inProgress
            : current.status,
        lastSessionAt: at ?? DateTime.now(),
        cumulativeRepeats: current.cumulativeRepeats + repeats,
      ),
    );
  }

  @override
  Future<void> clearSurah(int surahNumber, int ayahCount) async {
    final List<String> keys = <String>[
      for (int ayah = 1; ayah <= ayahCount; ayah++)
        MemorizationProgress.keyFor(surahNumber, ayah),
    ];
    try {
      await _requireBox.deleteAll(keys);
    } on StorageException {
      rethrow;
    } catch (e) {
      throw StorageException(
        'Could not clear progress for surah $surahNumber: $e',
      );
    }
  }

  @override
  Stream<void> watchChanges() => _requireBox.watch();

  MemorizationProgress _read(
    Map<dynamic, dynamic> stored,
    int surahNumber,
    int ayahNumber,
  ) {
    try {
      return MemorizationProgress.fromMap(stored);
    } catch (e) {
      throw StorageException(
        'Stored progress for $surahNumber:$ayahNumber is malformed: $e',
      );
    }
  }
}
