import 'package:dartz/dartz.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failures.dart';
import '../../../core/state/load_status.dart';
import '../../../data/models/mushaf_line.dart';
import '../../../data/models/surah.dart';
import '../../../data/models/word.dart';
import '../../../data/repositories/quran_pages_repository.dart';
import '../../../data/repositories/quran_repository.dart';
import 'mushaf_page.dart';
import 'mushaf_state.dart';

/// The mushaf, page by page, straight from `quran.db`'s layout.
///
/// Everything a page is made of comes from data: which lines it has, what
/// each line is, which words sit on it, whether a surah has a basmala line at
/// all. Nothing here knows a page or surah number.
///
/// [highlightAyah] and [goToAyah] are the entry points for anything outside
/// the screen — playback, a deep link — that needs an ayah on screen and
/// marked.
class MushafCubit extends Cubit<MushafState> {
  MushafCubit({
    required QuranPagesRepository pagesRepository,
    required QuranRepository quranRepository,
  }) : _pages = pagesRepository,
       _quran = quranRepository,
       super(const MushafState());

  final QuranPagesRepository _pages;
  final QuranRepository _quran;

  Map<int, Surah> _surahs = const <int, Surah>{};
  List<Word> _basmalaWords = const <Word>[];

  /// Builds in flight, so a second caller waits for the first rather than
  /// returning before the page exists.
  final Map<int, Future<void>> _building = <int, Future<void>>{};
  int _requestToken = 0;

  /// Opens at [initialAyah]'s page when given, otherwise at [initialPage].
  Future<void> init({AyahRef? initialAyah, int initialPage = 1}) async {
    emit(state.copyWith(status: LoadStatus.loading));
    try {
      final int pageCount = await _unwrap(_pages.pageCount());
      final int linesPerFullPage = await _unwrap(_pages.linesPerFullPage());
      final List<Surah> surahs = await _unwrap(_quran.getSurahs());
      final int start = initialAyah == null
          ? initialPage.clamp(1, pageCount)
          : await _unwrap(
              _pages.pageForAyah(initialAyah.surah, initialAyah.ayah),
            );

      _surahs = <int, Surah>{for (final Surah s in surahs) s.number: s};
      _basmalaWords = await _basmalaSource(surahs);
      if (isClosed) return;

      emit(
        state.copyWith(
          status: LoadStatus.ready,
          pageCount: pageCount,
          linesPerFullPage: linesPerFullPage,
          initialPage: start,
          currentPage: start,
          highlighted: initialAyah,
        ),
      );
      await ensurePage(start);
      _warmNeighbours(start);
    } on _Failed catch (e) {
      if (!isClosed) {
        emit(
          state.copyWith(
            status: LoadStatus.failure,
            errorMessage: e.failure.message,
          ),
        );
      }
    }
  }

  /// The basmala as quran.db stores it: ayah 1 of the surah whose basmala is
  /// counted as that ayah, minus its ayah-number marker. Empty — and the line
  /// drawn blank — if there is no such surah; the words are never typed.
  Future<List<Word>> _basmalaSource(List<Surah> surahs) async {
    final Surah? source = surahs
        .where((Surah s) => s.bismillahMode == BismillahMode.countedAsAyah1)
        .firstOrNull;
    if (source == null) return const <Word>[];
    return (await _pages.wordsForAyah(source.number, 1))
        .getOrElse(() => const <Word>[])
        .where((Word w) => !w.isMarker)
        .toList(growable: false);
  }

  /// Builds [page] if it is not already built; completes once it is (or has
  /// failed). Concurrent calls for one page share a single build.
  Future<void> ensurePage(int page) {
    if (page < 1 || page > state.pageCount) return Future<void>.value();
    if (state.pages.containsKey(page)) return Future<void>.value();
    return _building[page] ??= _build(page).whenComplete(() {
      // A block, not an arrow: `remove` returns this very future, and
      // whenComplete waits on whatever its callback returns.
      _building.remove(page);
    });
  }

  Future<void> _build(int page) async {
    final Either<Failure, MushafPage> built = await _buildPage(page);
    if (isClosed) return;

    built.fold(
      (Failure f) => emit(
        state.copyWith(
          failedPages: <int, String>{...state.failedPages, page: f.message},
        ),
      ),
      (MushafPage p) => emit(
        state.copyWith(
          pages: <int, MushafPage>{...state.pages, page: p},
          failedPages: <int, String>{...state.failedPages}..remove(page),
        ),
      ),
    );
  }

  Future<Either<Failure, MushafPage>> _buildPage(int page) async {
    try {
      final List<MushafLine> lines = await _unwrap(_pages.linesForPage(page));

      // One query for every word on the page, then each line takes its range.
      final List<MushafLine> ranged = <MushafLine>[
        for (final MushafLine l in lines)
          if (l.lineType == LineType.ayah &&
              l.firstWordId != null &&
              l.lastWordId != null)
            l,
      ];
      final Map<int, Word> byId = ranged.isEmpty
          ? const <int, Word>{}
          : <int, Word>{
              for (final Word w in await _unwrap(
                _pages.wordsInRange(
                  ranged.map((MushafLine l) => l.firstWordId!).reduce(_min),
                  ranged.map((MushafLine l) => l.lastWordId!).reduce(_max),
                ),
              ))
                w.id: w,
            };

      return Right<Failure, MushafPage>(
        MushafPage(
          number: page,
          lines: <PageLine>[
            for (final MushafLine line in lines) _lineFrom(line, byId),
          ],
        ),
      );
    } on _Failed catch (e) {
      return Left<Failure, MushafPage>(e.failure);
    }
  }

  PageLine _lineFrom(MushafLine line, Map<int, Word> byId) {
    switch (line.lineType) {
      case LineType.surahName:
        final Surah? surah = _surahs[line.surahNumber];
        if (surah == null) {
          throw _Failed(
            CatalogValidationFailure(
              'quran.db',
              'Page ${line.page} line ${line.line} opens surah '
                  '${line.surahNumber}, which is not in the catalog.',
            ),
          );
        }
        return SurahHeaderLine(surah);
      case LineType.basmala:
        return BasmalaLine(_basmalaWords);
      case LineType.ayah:
        final int? first = line.firstWordId;
        final int? last = line.lastWordId;
        return AyahLine(
          words: <Word>[
            if (first != null && last != null)
              for (int id = first; id <= last; id++)
                if (byId[id] case final Word w) w,
          ],
          centered: line.isCentered,
        );
    }
  }

  static int _min(int a, int b) => a < b ? a : b;
  static int _max(int a, int b) => a > b ? a : b;

  static Future<T> _unwrap<T>(Future<Either<Failure, T>> result) async =>
      (await result).fold((Failure f) => throw _Failed(f), (T value) => value);

  void onPageChanged(int page) {
    if (page == state.currentPage) return;
    emit(state.copyWith(currentPage: page));
    ensurePage(page);
    _warmNeighbours(page);
  }

  void _warmNeighbours(int page) {
    ensurePage(page - 1);
    ensurePage(page + 1);
  }

  // --- the public API -------------------------------------------------------

  /// Tints every word of [surah]:[ayah].
  void highlightAyah(int surah, int ayah) =>
      emit(state.copyWith(highlighted: AyahRef(surah, ayah)));

  void clearHighlight() => emit(state.copyWith(clearHighlighted: true));

  /// Brings the page holding [surah]:[ayah] on screen, animated.
  Future<void> goToAyah(int surah, int ayah) async {
    final Either<Failure, int> page = await _pages.pageForAyah(surah, ayah);
    if (isClosed) return;
    await page.fold(
      (Failure f) async => emit(state.copyWith(errorMessage: f.message)),
      (int p) async {
        await ensurePage(p);
        if (isClosed) return;
        emit(
          state.copyWith(
            pageRequest: PageRequest(page: p, token: ++_requestToken),
          ),
        );
      },
    );
  }

  // --- selection ------------------------------------------------------------

  /// A tap on a word. Ayah-number markers are not part of any ayah's text and
  /// select nothing.
  void selectWord(Word word) {
    if (word.isMarker) return;
    emit(state.copyWith(selected: AyahRef(word.surahNumber, word.ayahNumber)));
  }

  void clearSelection() => emit(state.copyWith(clearSelected: true));

  Surah? surahFor(int number) => _surahs[number];
}

/// Carries a [Failure] out of a chain of repository calls.
class _Failed implements Exception {
  const _Failed(this.failure);

  final Failure failure;
}
