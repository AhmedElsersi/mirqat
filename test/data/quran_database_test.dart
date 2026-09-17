import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/constants/app_constants.dart';
import 'package:mirqat/data/datasources/quran_database.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opens the bundled `quran.db` the same way the app does — through
/// [QuranDatabase], not a raw `sqlite3` connection — so a broken copy step
/// or a wrong read-only flag would fail here too, not just the shape checks.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory storageDir;
  late QuranDatabase quranDatabase;

  setUp(() {
    storageDir = Directory.systemTemp.createTempSync('quran_db_test');
    quranDatabase = QuranDatabase(
      factory: databaseFactoryFfi,
      resolveStorageDirectory: () async => storageDir,
    );
  });

  tearDown(() {
    if (storageDir.existsSync()) storageDir.deleteSync(recursive: true);
  });

  test('copies the bundled asset out and opens it read-only', () async {
    final Database db = await quranDatabase.open();
    expect(db.isOpen, isTrue);

    // Read-only: sqflite surfaces this as a failed write, not a flag to
    // introspect directly.
    await expectLater(
      db.execute("INSERT INTO meta (key, value) VALUES ('x', 'x')"),
      throwsA(anything),
    );
  });

  test('114 surahs, 6236 ayahs, 604 distinct pages', () async {
    final Database db = await quranDatabase.open();

    expect(
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM surahs')),
      114,
    );
    expect(
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM ayahs')),
      6236,
    );
    expect(
      Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(DISTINCT page) FROM lines'),
      ),
      604,
    );
  });

  test(
    'page 1 line 1 is the surah_name line for surah 1',
    () async {
      final Database db = await quranDatabase.open();
      final List<Map<String, Object?>> rows = await db.query(
        'lines',
        where: 'page = ? AND line = ?',
        whereArgs: <int>[1, 1],
      );

      expect(rows, hasLength(1));
      expect(rows.single['line_type'], 'surah_name');
      expect(rows.single['surah_number'], 1);
    },
  );

  test('the bundled schema_version matches the app constant', () async {
    // A schema change without a bump leaves every installed quran_v<n>.db in
    // place, opened read-only with the old columns, forever.
    final Database db = await quranDatabase.open();
    final List<Map<String, Object?>> rows = await db.query(
      'meta',
      where: 'key = ?',
      whereArgs: <String>['schema_version'],
    );
    expect(rows.single['value'], '${AppConstants.quranDatabaseSchemaVersion}');
  });

  test('reopening returns the same database instance without re-copying', () async {
    final Database first = await quranDatabase.open();
    final Database second = await quranDatabase.open();
    expect(identical(first, second), isTrue);
  });
}
