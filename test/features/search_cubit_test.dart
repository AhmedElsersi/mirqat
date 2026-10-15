import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/data/datasources/quran_pages_local_data_source.dart';
import 'package:mirqat/data/models/ayah_search_hit.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:mirqat/data/repositories/quran_pages_repository.dart';
import 'package:mirqat/features/search/cubit/search_cubit.dart';
import 'package:mirqat/features/search/cubit/search_state.dart';

import '../quran_db_fixtures.dart';

/// Search over the real `assets/data/quran.db`: a surah by name, an ayah by
/// its words, a page by its number — all catalogue facts, nothing of them
/// written in the app (CLAUDE.md A.2 rule 2).
void main() {
  late SearchCubit cubit;

  setUp(() async {
    cubit = SearchCubit(
      repositoryOverRealDatabase(),
      QuranPagesRepositoryImpl(
        QuranPagesLocalDataSourceImpl(RepoQuranDatabase()),
      ),
    );
    await cubit.load();
  });

  tearDown(() => cubit.close());

  test('a surah by name, however the hamza and taa marbuta are typed',
      () async {
    await cubit.search('الفاتحه');
    expect(
      cubit.state.surahs.map((Surah s) => s.number),
      contains(1),
    );

    await cubit.search('Ikhlas');
    expect(
      cubit.state.surahs.map((Surah s) => s.number),
      contains(112),
    );
  });

  test('an ayah by its words, typed without the rasm\'s letters', () async {
    await cubit.search('قل هو الله أحد');
    expect(
      cubit.state.ayahs,
      contains(
        isA<AyahSearchHit>()
            .having((AyahSearchHit h) => h.surahNumber, 'surah', 112)
            .having((AyahSearchHit h) => h.number, 'ayah', 1),
      ),
    );
    // What a hit shows is the stored text, byte for byte — read from the
    // database here, never typed into the test (A.2 rule 1).
    final AyahSearchHit hit = cubit.state.ayahs.firstWhere(
      (AyahSearchHit h) => h.surahNumber == 112 && h.number == 1,
    );
    final String stored =
        (await (await RepoQuranDatabase().open()).rawQuery(
              'SELECT text FROM ayahs WHERE surah = 112 AND ayah = 1',
            )).single['text']!
            as String;
    expect(hit.text.codeUnits, stored.codeUnits);
    expect(hit.page, 604);
  });

  test('a number is a page while the mushaf has one, and only then', () async {
    await cubit.search('٦٠٤');
    expect(cubit.state.page, 604);

    await cubit.search('605');
    expect(cubit.state.page, isNull);

    await cubit.search('0');
    expect(cubit.state.page, isNull);
  });

  test('clearing the query clears the results', () async {
    await cubit.search('نوح');
    expect(cubit.state.hasResults, isTrue);

    await cubit.search('  ');
    expect(cubit.state, const SearchState());
  });

  test('the ayah list is capped, never an ayah\'s text', () async {
    // One common letter matches thousands of ayahs.
    await cubit.search('من');
    expect(cubit.state.ayahs.length, SearchCubit.ayahLimit);
  });

  test('a stale answer never lands over a newer query', () async {
    // Fire without awaiting, then overtake it.
    final Future<void> slow = cubit.search('الرحمن الرحيم');
    await cubit.search('نوح');
    await slow;
    expect(cubit.state.query, 'نوح');
    // The newer query's hits stand; the older answer was dropped. 1:1 is a
    // «الرحمن الرحيم» hit and holds no نوح.
    expect(
      cubit.state.ayahs,
      isNot(
        contains(
          isA<AyahSearchHit>()
              .having((AyahSearchHit h) => h.surahNumber, 'surah', 1)
              .having((AyahSearchHit h) => h.number, 'ayah', 1),
        ),
      ),
    );
  });
}
