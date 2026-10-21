import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:mirqat/data/datasources/practice_local_data_source.dart';
import 'package:mirqat/data/datasources/progress_local_data_source.dart';
import 'package:mirqat/data/models/memorization_progress.dart';
import 'package:mirqat/domain/entities/practice_stats.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mirqat_practice_test');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('a day adds up across sessions, and survives a restart', () async {
    final PracticeLocalDataSourceImpl first = PracticeLocalDataSourceImpl();
    await first.open();
    await first.add(
      DateTime(2026, 11, 2, 7),
      const PracticeDay(plays: 3, seconds: 40),
    );
    await first.add(
      DateTime(2026, 11, 2, 22),
      const PracticeDay(plays: 5, seconds: 100),
    );
    await first.add(
      DateTime(2026, 11, 3),
      const PracticeDay(plays: 1, seconds: 5),
    );

    await Hive.close();
    Hive.init(dir.path);
    final PracticeLocalDataSourceImpl second = PracticeLocalDataSourceImpl();
    await second.open();
    expect(await second.all(), <DateTime, PracticeDay>{
      DateTime(2026, 11, 2): const PracticeDay(plays: 8, seconds: 140),
      DateTime(2026, 11, 3): const PracticeDay(plays: 1, seconds: 5),
    });
  });

  test('a record that cannot be read is left out', () async {
    final PracticeLocalDataSourceImpl s = PracticeLocalDataSourceImpl();
    await s.open();
    await s.add(DateTime(2026, 11, 2), const PracticeDay(plays: 1));
    final Box<Map<dynamic, dynamic>> box = Hive.box<Map<dynamic, dynamic>>(
      'practice_days',
    );
    await box.put('yesterday', <String, dynamic>{'plays': 1, 'seconds': 1});
    await box.put('2026-11-04', <String, dynamic>{'plays': 'many'});
    expect((await s.all()).keys, <DateTime>[DateTime(2026, 11, 2)]);
  });

  test('ayahs marked memorized are counted, nothing else', () async {
    final ProgressLocalDataSourceImpl p = ProgressLocalDataSourceImpl();
    await p.open();
    await p.setStatus(1, 1, MemorizationStatus.memorized);
    await p.setStatus(1, 2, MemorizationStatus.memorized);
    await p.recordRepeats(1, 3, 4);
    await Hive.box<Map<dynamic, dynamic>>(
      'memorization_progress',
    ).put('junk', <String, dynamic>{'status': 'memorized'});
    expect(await p.memorizedCount(), 2);
  });
}
