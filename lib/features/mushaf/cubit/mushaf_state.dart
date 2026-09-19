import 'package:equatable/equatable.dart';

import '../../../core/state/load_status.dart';
import 'mushaf_page.dart';

/// A request for the screen to bring [page] into view. [token] changes on
/// every request, so asking for the page already on screen still counts.
class PageRequest extends Equatable {
  const PageRequest({required this.page, required this.token});

  final int page;
  final int token;

  @override
  List<Object?> get props => <Object?>[page, token];
}

class MushafState extends Equatable {
  const MushafState({
    this.status = LoadStatus.initial,
    this.pageCount = 0,
    this.linesPerFullPage = 0,
    this.initialPage = 1,
    this.currentPage = 1,
    this.pages = const <int, MushafPage>{},
    this.failedPages = const <int, String>{},
    this.highlighted,
    this.selected,
    this.pageRequest,
    this.errorMessage,
  });

  final LoadStatus status;
  final int pageCount;

  /// The line count a full page is laid out for, so a short page (the opening
  /// two) keeps the same line pitch instead of blowing its text up.
  final int linesPerFullPage;

  final int initialPage;
  final int currentPage;

  /// Pages built so far, by number. Built on demand, never all 604 at once.
  final Map<int, MushafPage> pages;
  final Map<int, String> failedPages;

  /// Tinted from outside — the ayah being recited.
  final AyahRef? highlighted;

  /// Tinted because the reader tapped it.
  final AyahRef? selected;

  final PageRequest? pageRequest;
  final String? errorMessage;

  MushafState copyWith({
    LoadStatus? status,
    int? pageCount,
    int? linesPerFullPage,
    int? initialPage,
    int? currentPage,
    Map<int, MushafPage>? pages,
    Map<int, String>? failedPages,
    AyahRef? highlighted,
    bool clearHighlighted = false,
    AyahRef? selected,
    bool clearSelected = false,
    PageRequest? pageRequest,
    String? errorMessage,
  }) => MushafState(
    status: status ?? this.status,
    pageCount: pageCount ?? this.pageCount,
    linesPerFullPage: linesPerFullPage ?? this.linesPerFullPage,
    initialPage: initialPage ?? this.initialPage,
    currentPage: currentPage ?? this.currentPage,
    pages: pages ?? this.pages,
    failedPages: failedPages ?? this.failedPages,
    highlighted: clearHighlighted ? null : (highlighted ?? this.highlighted),
    selected: clearSelected ? null : (selected ?? this.selected),
    pageRequest: pageRequest ?? this.pageRequest,
    errorMessage: errorMessage ?? this.errorMessage,
  );

  @override
  List<Object?> get props => <Object?>[
    status,
    pageCount,
    linesPerFullPage,
    initialPage,
    currentPage,
    pages,
    failedPages,
    highlighted,
    selected,
    pageRequest,
    errorMessage,
  ];
}
