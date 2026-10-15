import 'package:equatable/equatable.dart';

import '../../../data/models/ayah_search_hit.dart';
import '../../../data/models/surah.dart';

/// What a search found for the query as typed: a page, surahs, ayahs — any
/// mix, shown together.
class SearchState extends Equatable {
  const SearchState({
    this.query = '',
    this.page,
    this.surahs = const <Surah>[],
    this.ayahs = const <AyahSearchHit>[],
    this.searching = false,
  });

  /// The query exactly as typed.
  final String query;

  /// The page the query names, when it is a number within the mushaf.
  final int? page;

  /// Surahs whose Arabic name or transliteration matches.
  final List<Surah> surahs;

  /// Ayahs whose words match, in mushaf order, capped at
  /// `SearchCubit.ayahLimit`.
  final List<AyahSearchHit> ayahs;

  /// Whether an answer for [query] is still on its way.
  final bool searching;

  bool get hasQuery => query.trim().isNotEmpty;

  bool get hasResults => page != null || surahs.isNotEmpty || ayahs.isNotEmpty;

  SearchState copyWith({
    String? query,
    int? page,
    bool clearPage = false,
    List<Surah>? surahs,
    List<AyahSearchHit>? ayahs,
    bool? searching,
  }) => SearchState(
    query: query ?? this.query,
    page: clearPage ? null : (page ?? this.page),
    surahs: surahs ?? this.surahs,
    ayahs: ayahs ?? this.ayahs,
    searching: searching ?? this.searching,
  );

  @override
  List<Object?> get props => <Object?>[query, page, surahs, ayahs, searching];
}
