import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:mirqat/data/datasources/review_local_data_source.dart';
import 'package:mirqat/domain/engine/review_scheduler.dart';
import 'package:mirqat/domain/entities/ayah_ref.dart';
import 'package:mirqat/domain/entities/review_card.dart';

void main() {
  late Directory dir;
  const ReviewScheduler scheduler = ReviewScheduler();

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mirqat_review_test');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<ReviewLocalDataSource> open() async {
    final ReviewLocalDataSourceImpl s = ReviewLocalDataSourceImpl();
    await s.open();
    return s;
  }

  ReviewCard card(int surah) => scheduler.start(
    from: AyahRef(surah, 1),
    to: AyahRef(surah, 4),
    grade: Grade.solid,
    now: DateTime(2026, 10, 19, 9),
  );

  test('cards survive a restart', () async {
    final ReviewLocalDataSource first = await open();
    await first.save(card(67));
    await first.save(card(78));

    await Hive.close();
    Hive.init(dir.path);

    final ReviewLocalDataSource second = await open();
    final List<ReviewCard> all = await second.all();
    expect(all.map((ReviewCard c) => c.id).toSet(), <String>{
      '67:1-67:4',
      '78:1-78:4',
    });
    expect(await second.get('67:1-67:4'), card(67));
  });

  test('grading the same range writes over its card, not beside it', () async {
    final ReviewLocalDataSource s = await open();
    await s.save(card(67));
    await s.save(
      scheduler.grade(card(67), Grade.forgot, DateTime(2026, 10, 21)),
    );
    final List<ReviewCard> all = await s.all();
    expect(all, hasLength(1));
    expect(all.single.lastGrade, Grade.forgot);
  });

  test('a malformed record costs that record, never the list', () async {
    final ReviewLocalDataSource s = await open();
    await s.save(card(67));
    await Hive.box<Map<dynamic, dynamic>>(
      'review_cards',
    ).put('junk', <String, dynamic>{'from': 'nowhere'});
    expect((await s.all()).single.id, '67:1-67:4');
    expect(await s.get('junk'), isNull);
  });

  test('deleting forgets one card', () async {
    final ReviewLocalDataSource s = await open();
    await s.save(card(67));
    await s.save(card(78));
    await s.delete('67:1-67:4');
    expect((await s.all()).single.id, '78:1-78:4');
  });
}
