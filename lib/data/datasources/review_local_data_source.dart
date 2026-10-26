import 'package:hive_ce/hive.dart';

import '../../core/constants/app_constants.dart';
import '../../core/error/exceptions.dart';
import '../../domain/entities/review_card.dart';

/// The review ladder, kept on the device and nowhere else (CLAUDE.md A.2
/// rule 3): one plain map per card in a `hive_ce` box, keyed by the card's
/// range, with no generated adapter (A.4).
abstract class ReviewLocalDataSource {
  Future<void> open();

  /// Every card that can be read. One that cannot is left out — losing one
  /// card is nothing next to losing the list.
  Future<List<ReviewCard>> all();

  Future<ReviewCard?> get(String id);

  Future<void> save(ReviewCard card);

  Future<void> delete(String id);

  /// Fires whenever a card is written or deleted.
  Stream<void> watchChanges();
}

class ReviewLocalDataSourceImpl implements ReviewLocalDataSource {
  ReviewLocalDataSourceImpl({String? boxName})
    : _boxName = boxName ?? AppConstants.reviewCardsBoxName;

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
        'Review cards were used before open() was called.',
      );
    }
    return box;
  }

  @override
  Future<List<ReviewCard>> all() async => <ReviewCard>[
    for (final Object? stored in _requireBox.values)
      ?ReviewCard.fromMap(stored),
  ];

  @override
  Future<ReviewCard?> get(String id) async =>
      ReviewCard.fromMap(_requireBox.get(id));

  @override
  Future<void> save(ReviewCard card) async {
    try {
      await _requireBox.put(card.id, card.toMap());
    } on StorageException {
      rethrow;
    } catch (e) {
      throw StorageException('Could not save review card ${card.id}: $e');
    }
  }

  @override
  Future<void> delete(String id) async {
    try {
      await _requireBox.delete(id);
    } on StorageException {
      rethrow;
    } catch (e) {
      throw StorageException('Could not delete review card $id: $e');
    }
  }

  @override
  Stream<void> watchChanges() => _requireBox.watch();
}
