import 'package:dartz/dartz.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failures.dart';
import '../../../core/search/search_text.dart';
import '../../../data/models/ayah_search_hit.dart';
import '../../../data/models/surah.dart';
import '../../../data/repositories/quran_pages_repository.dart';
import '../../../data/repositories/quran_repository.dart';
import 'search_state.dart';

/// Answers one box with three kinds of result: a page for a number, surahs
/// for a name, ayahs for words.
///
/// The ayah matching happens in SQL against `quran.db`'s `text_search`
/// column, which was computed at build time — no Quranic text is normalised
/// here or anywhere in the app (CLAUDE.md A.2 rule 1). What this cubit
/// normalises is the *query*, and the surah names, which are labels.
class SearchCubit extends Cubit<SearchState> {
  SearchCubit(this._quran, this._pages) : super(const SearchState());

  final QuranRepository _quran;
  final QuranPagesRepository _pages;

  /// The most ayah hits one search shows. A cap on the result list, never on
  /// any ayah's text: each hit shown is shown whole (CLAUDE.md A.2 rule 7).
  static const int ayahLimit = 100;

  /// A needle this short matches most of the mushaf; asking for more letters
  /// is a better answer than a thousand hits.
  static const int minNeedleLength = 2;

  List<Surah> _surahs = const <Surah>[];
  Map<int, Surah> _surahsByNumber = const <int, Surah>{};
  int _pageCount = 0;

  /// Supersedes stale answers: only the latest query may emit results.
  int _generation = 0;

  Future<void> load() async {
    _surahs = (await _quran.getSurahs()).fold(
      (Failure _) => const <Surah>[],
      (List<Surah> s) => s,
    );
    _surahsByNumber = <int, Surah>{
      for (final Surah s in _surahs) s.number: s,
    };
    _pageCount = (await _pages.pageCount()).fold((Failure _) => 0, (int n) => n);
  }

  /// The surah [surahNumber], for naming an ayah hit. Null before [load].
  Surah? surahOf(int surahNumber) => _surahsByNumber[surahNumber];

  /// The mushaf page [surahNumber] begins on, or null if the catalog cannot
  /// say — the same lookup the home screen makes to open a surah.
  Future<int?> pageOfSurah(int surahNumber) async =>
      (await _pages.pageForAyah(surahNumber, 1)).fold(
        (Failure _) => null,
        (int p) => p,
      );

  Future<void> search(String input) async {
    final int generation = ++_generation;
    if (input.trim().isEmpty) {
      emit(const SearchState());
      return;
    }

    // A number is a page request; everything else is a name or words.
    final int? pageQuery = pageNumberQuery(input);
    final int? page =
        pageQuery != null && pageQuery >= 1 && pageQuery <= _pageCount
        ? pageQuery
        : null;

    // An Arabic query reduces to a needle; a Latin one reduces to nothing,
    // and matches surahs by their transliteration instead.
    final String needle = searchableQuery(input);
    final List<Surah> surahs = _matchingSurahs(input, needle);

    emit(
      SearchState(
        query: input,
        page: page,
        surahs: surahs,
        ayahs: const <AyahSearchHit>[],
        searching: needle.length >= minNeedleLength,
      ),
    );
    if (needle.length < minNeedleLength) return;

    final Either<Failure, List<AyahSearchHit>> hits = await _quran.searchAyahs(
      needle,
      limit: ayahLimit,
    );
    if (generation != _generation || isClosed) return;
    emit(
      state.copyWith(
        ayahs: hits.fold(
          // A failed read degrades to "no ayah hits", quietly: the page and
          // surah answers above still stand.
          (Failure _) => const <AyahSearchHit>[],
          (List<AyahSearchHit> found) => found,
        ),
        searching: false,
      ),
    );
  }

  static final RegExp _latinLetters = RegExp('[a-z]');

  List<Surah> _matchingSurahs(String input, String needle) {
    final String latin = input.trim().toLowerCase();
    final bool byLatin = _latinLetters.hasMatch(latin);
    if (needle.isEmpty && !byLatin) return const <Surah>[];
    return List<Surah>.unmodifiable(
      _surahs.where(
        (Surah s) =>
            (needle.isNotEmpty &&
                searchableQuery(s.nameAr).contains(needle)) ||
            (byLatin && s.nameEn.toLowerCase().contains(latin)),
      ),
    );
  }
}
