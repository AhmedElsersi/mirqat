import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/data/models/app_settings.dart';
import 'package:mirqat/data/models/reading_position.dart';
import 'package:mirqat/features/home/cubit/home_index_state.dart';

ReadingPosition at(int page) => ReadingPosition(
  surahNumber: 4,
  ayahNumber: 12,
  page: page,
  at: DateTime(2026, 9, 20),
);

/// Where the app opens. Checked as a rule rather than by launching into the
/// mushaf: a mushaf started under a widget test's fake clock never finishes
/// its first database read, and leaves the connection stuck for every test
/// after it. The launch itself is checked on a device.
void main() {
  test('the mushaf view opens straight onto the last page read', () {
    expect(launchPage(mode: HomeViewMode.mushaf, last: at(77)), 77);
  });

  test('the mushaf view opens on page 1 when nothing has been read', () {
    expect(launchPage(mode: HomeViewMode.mushaf, last: null), 1);
  });

  test('list and grid open on the index, wherever the reader was', () {
    // The last place is one tap away there — the card and the history
    // button — but the app does not jump to it.
    for (final HomeViewMode mode in <HomeViewMode>[
      HomeViewMode.list,
      HomeViewMode.grid,
    ]) {
      expect(
        launchPage(mode: mode, last: at(77)),
        isNull,
        reason: mode.name,
      );
      expect(launchPage(mode: mode, last: null), isNull, reason: mode.name);
    }
  });

  test('every view mode has an answer', () {
    for (final HomeViewMode mode in HomeViewMode.values) {
      expect(() => launchPage(mode: mode, last: at(3)), returnsNormally);
    }
  });
}
