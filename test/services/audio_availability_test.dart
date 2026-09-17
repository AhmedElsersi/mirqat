import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/error/failures.dart';
import 'package:mirqat/data/models/reciter.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:mirqat/data/repositories/quran_repository.dart';
import 'package:mirqat/services/audio/audio_availability.dart';

import '../quran_db_fixtures.dart';

void main() {
  late QuranRepository repository;
  late AudioAvailability availability;

  setUp(() {
    repository = fixtureRepository();
    availability = AudioAvailability(quranRepository: repository);
  });

  Future<List<String>> idsFor(int surahNumber) async {
    final Surah surah = (await repository.getSurah(
      surahNumber,
    )).getOrElse(() => throw StateError('no surah $surahNumber'));
    return (await availability.recitersFor(surah))
        .getOrElse(() => throw StateError('lookup failed'))
        .map((Reciter r) => r.id)
        .toList();
  }

  test('lists every reciter that has the surah, in catalog order', () async {
    expect(await idsFor(1), <String>['a', 'b']);
    expect(await idsFor(2), <String>['b']);
  });

  test('is empty for a surah nobody has recorded', () async {
    expect(await idsFor(3), isEmpty);
  });

  test('the catalog lists every surah regardless of audio', () async {
    expect(
      (await repository.getSurahs())
          .getOrElse(() => <Surah>[])
          .map((Surah s) => s.number),
      <int>[1, 2, 3],
    );
  });

  test('a reciter catalog that fails to load is a Left, not an empty '
      'answer', () async {
    final QuranRepository broken = fixtureRepository(reciters: '[{');
    final Surah surah = (await broken.getSurah(
      1,
    )).getOrElse(() => throw StateError('no surah 1'));
    final result = await AudioAvailability(
      quranRepository: broken,
    ).recitersFor(surah);
    expect(result.isLeft(), isTrue);
    result.fold(
      (Failure f) => expect(f, isA<AssetParseFailure>()),
      (_) => fail('expected a Left'),
    );
  });
}
