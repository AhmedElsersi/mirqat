import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/juz_info.dart';
import '../../../data/models/reading_position.dart';
import '../../../data/models/surah.dart';
import '../../../data/repositories/quran_pages_repository.dart';
import '../../../data/repositories/quran_repository.dart';
import '../../../data/repositories/reading_history_repository.dart';
import 'home_index_state.dart';

/// What the home screen shows besides the surah list: the ajzaa, and where
/// the reader has been. Shared with the history screen, which is the same
/// list in full.
///
/// Everything here is a convenience over reading, so nothing here fails
/// loudly: a juz list that will not load is an empty tab, and a history that
/// will not load is no "continue" card — never an error over the home screen.
class HomeIndexCubit extends Cubit<HomeIndexState> {
  HomeIndexCubit({
    required QuranRepository quranRepository,
    required QuranPagesRepository pagesRepository,
    required ReadingHistoryRepository historyRepository,
  }) : _quran = quranRepository,
       _pages = pagesRepository,
       _history = historyRepository,
       super(const HomeIndexState());

  final QuranRepository _quran;
  final QuranPagesRepository _pages;
  final ReadingHistoryRepository _history;

  Map<int, Surah> _surahs = const <int, Surah>{};

  Future<void> load() async {
    _surahs = <int, Surah>{
      for (final Surah s in (await _quran.getSurahs()).getOrElse(
        () => const <Surah>[],
      ))
        s.number: s,
    };
    final List<JuzInfo> ajzaa = (await _pages.juzList()).getOrElse(
      () => const <JuzInfo>[],
    );
    if (isClosed) return;

    emit(
      state.copyWith(
        ajzaa: <JuzItem>[
          for (final JuzInfo j in ajzaa)
            if (_surahs[j.surahNumber] case final Surah s)
              JuzItem(info: j, surah: s),
        ],
        history: await _readHistory(),
        loaded: true,
      ),
    );
  }

  /// Re-reads the history — after coming back from a reading screen, which is
  /// what writes it.
  Future<void> refreshHistory() async {
    final List<PlaceItem> history = await _readHistory();
    if (!isClosed) emit(state.copyWith(history: history));
  }

  Future<List<PlaceItem>> _readHistory() async => <PlaceItem>[
    for (final ReadingPosition p in (await _history.history()).getOrElse(
      () => const <ReadingPosition>[],
    ))
      if (_surahs[p.surahNumber] case final Surah s)
        PlaceItem(position: p, surah: s),
  ];

  /// The surah with this number, as the catalog names it, or null.
  Surah? surahOf(int surahNumber) => _surahs[surahNumber];

  /// The mushaf page a surah begins on, or null if the catalog cannot say.
  Future<int?> pageOfSurah(int surahNumber) async => (await _pages.pageForAyah(
    surahNumber,
    1,
  )).fold((_) => null, (int p) => p);

  Future<void> clearHistory() async {
    await _history.clear();
    await refreshHistory();
  }
}
