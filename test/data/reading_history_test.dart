import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/data/datasources/reading_history_local_data_source.dart';
import 'package:mirqat/data/models/reading_position.dart';
import 'package:mirqat/data/repositories/reading_history_repository.dart';

class _Memory implements ReadingHistoryLocalDataSource {
  List<ReadingPosition> stored = const <ReadingPosition>[];

  @override
  Future<void> open() async {}

  @override
  Future<List<ReadingPosition>> read() async => stored;

  @override
  Future<void> write(List<ReadingPosition> positions) async =>
      stored = positions;
}

ReadingPosition at(int page, {int surah = 2, int ayah = 1, int minute = 0}) =>
    ReadingPosition(
      surahNumber: surah,
      ayahNumber: ayah,
      page: page,
      at: DateTime(2026, 9, 20, 10, minute),
    );

List<int> pages(List<ReadingPosition> list) => <int>[
  for (final ReadingPosition p in list) p.page,
];

/// "Open where I left off", and the list of where that has been. The rules
/// here decide whether the history is useful or just a log of page turns.
void main() {
  late _Memory memory;
  late ReadingHistoryRepository history;

  setUp(() {
    memory = _Memory();
    history = ReadingHistoryRepositoryImpl(memory);
  });

  test('a fresh install has no last position', () async {
    expect((await history.last()).getOrElse(() => at(0)), isNull);
    expect(
      (await history.history()).getOrElse(() => <ReadingPosition>[]),
      isEmpty,
    );
  });

  test('a new visit goes on top, newest first', () async {
    await history.record(at(3));
    await history.record(at(50, surah: 3));
    expect(pages(memory.stored), <int>[50, 3]);
    expect((await history.last()).getOrElse(() => null)?.page, 50);
  });

  test('one sitting is one entry, however many pages are turned', () async {
    // Reading twenty pages must not push twenty other places out.
    await history.record(at(600, surah: 100));
    await history.record(at(3)); // a new visit opens on page 3…
    for (int page = 4; page <= 25; page++) {
      await history.record(at(page, minute: page), sameVisit: true);
    }
    expect(pages(memory.stored), <int>[25, 600]);
  });

  test(
    'coming back to the very place the last visit ended continues it',
    () async {
      await history.record(at(10, minute: 1));
      await history.record(at(10, minute: 30)); // a new visit, same page
      expect(pages(memory.stored), <int>[10]);
      expect(
        memory.stored.single.at.minute,
        30,
        reason: 'the time is brought up to date',
      );
    },
  );

  test('the same page in another surah is another place', () async {
    // Short surahs share a page: 112, 113 and 114 are all on 604.
    await history.record(at(604, surah: 112));
    await history.record(at(604, surah: 114));
    expect(memory.stored, hasLength(2));
  });

  test('only the last twenty places are kept, dropping the oldest', () async {
    for (int page = 1; page <= 30; page++) {
      await history.record(at(page));
    }
    expect(memory.stored, hasLength(ReadingHistoryRepositoryImpl.limit));
    expect(memory.stored.first.page, 30);
    expect(memory.stored.last.page, 11);
  });

  test('clearing forgets everything', () async {
    await history.record(at(3));
    await history.clear();
    expect(memory.stored, isEmpty);
  });

  test('a position survives being stored and read back', () {
    final ReadingPosition p = at(77, surah: 5, ayah: 12, minute: 42);
    expect(ReadingPosition.fromMap(p.toMap()), p);
  });
}
