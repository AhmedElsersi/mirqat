import 'dart:async';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../core/desktop.dart';
import '../../../core/di/injection.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../../core/router/app_routes.dart';
import '../../../domain/entities/playback_unit.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/state/load_status.dart';
import '../../../core/widgets/islamic_frame.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/mushaf_line.dart';
import '../../../data/models/ayah.dart';
import '../../../data/models/reading_position.dart';
import '../../../data/models/surah.dart';
import '../../../data/models/word.dart';
import '../../../data/models/mutashabihat.dart';
import '../../../data/repositories/mutashabihat_repository.dart';
import '../../../data/repositories/quran_repository.dart';
import '../../../services/qpc_font_service.dart';
import '../../../services/share_service.dart';
import '../../session/cubit/session_cubit.dart';
import '../../session/cubit/session_state.dart';
import '../../session/default_range.dart';
import '../../session/session_request.dart';
import '../../session/widgets/session_bar.dart';
import '../../session/widgets/session_sheet.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../settings/cubit/settings_state.dart';
import '../../surah_list/widgets/error_view.dart';
import '../cubit/mushaf_cubit.dart';
import '../cubit/mushaf_page.dart';
import '../cubit/mushaf_state.dart';
import '../mushaf_args.dart';
import '../reading_section.dart';
import '../widgets/ayah_actions_sheet.dart';
import '../widgets/ayah_share_dialog.dart';
import '../widgets/mushaf_fold.dart';
import '../widgets/mushaf_page_view.dart';
import '../widgets/page_share_dialog.dart';
import '../widgets/paper_turn.dart';

class MushafScreen extends StatelessWidget {
  const MushafScreen({this.args = const MushafArgs(), super.key});

  final MushafArgs args;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: <BlocProvider<dynamic>>[
        BlocProvider<MushafCubit>(
          create: (BuildContext context) => sl<MushafCubit>()
            ..init(
              initialAyah: args.initialAyah,
              initialPage: args.initialPage ?? 1,
              section: args.section,
              layout: MushafLayout.forFont(
                context.read<SettingsCubit>().state.settings.quranFont,
              ),
            ),
        ),
        // The session belongs to the reading screen: it plays over this text
        // and ends when the screen is left.
        BlocProvider<SessionCubit>(
          create: (_) {
            final SessionCubit session = sl<SessionCubit>();
            final SessionRequest? request = args.session;
            // A session asked for on the way in is set up once the catalog
            // and the reciters are known — by then the page is on screen to
            // follow it.
            session.load().then((_) {
              if (request != null && !session.isClosed) {
                session.applyRequest(request);
              }
            });
            return session;
          },
        ),
      ],
      child: const MushafView(),
    );
  }
}

/// The page turner, reading its cubit from context.
class MushafView extends StatefulWidget {
  const MushafView({super.key});

  @override
  State<MushafView> createState() => _MushafViewState();
}

class _MushafViewState extends State<MushafView> with WidgetsBindingObserver {
  /// The furthest [MushafCubit.goToAyah] animates rather than jumps.
  static const int _animatedPageSpan = 2;

  PageController? _controller;

  /// The run of pages [_controller] was made for. Another surah or juz is
  /// another run, with its own first page, and needs its own controller.
  int _controllerEpoch = -1;

  /// Whether the mushaf is lying open at two facing pages, as the last build
  /// settled it (`spreadFits`). Everything here that counts pages reads it:
  /// the pager's items are *leaves* of one page or two, and a leaf is what a
  /// swipe, an arrow key and a page request each move by.
  bool _spread = false;

  /// What [_spread] was when [_controller] was made. A window dragged past
  /// the width a spread needs renumbers every leaf, so the controller is
  /// remade at the leaf the reader is on.
  bool _controllerSpread = false;

  /// Whether the bottom bar is showing. It starts hidden: the screen opens on
  /// the page, whole, the way a book opens — and a tap anywhere brings the
  /// controls up, and another puts them away.
  bool _chrome = false;

  /// The bar's height, as last laid out: while it is up, each page gains this
  /// much room to scroll, so nothing printed stays hidden under it.
  double _barHeight = 0;

  double get _bottomInset => _chrome ? _barHeight : 0;

  /// Whether the page keeps up with the ayah being recited. Turning a page by
  /// hand lets go of it — the reader is looking at something else — and the
  /// chip that appears then takes it up again.
  bool _following = true;

  /// True between a finger going down on the pages and the scroll it started
  /// coming to rest: a page change in that window is the reader's doing, not
  /// the session's.
  bool _dragging = false;

  void _toggleChrome() => setState(() => _chrome = !_chrome);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  /// Going to the background is the last thing an app is reliably told before
  /// it may be closed, so that is when the page is written down once more.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && mounted) {
      context.read<MushafCubit>().recordPosition();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  PageController _controllerFor(MushafState state) {
    if (_controller == null ||
        _controllerEpoch != state.epoch ||
        _controllerSpread != _spread) {
      final PageController? old = _controller;
      // Disposed after the frame: the old page view is still attached to it
      // until this build has replaced that view.
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
      // The same run of pages, renumbered because the window crossed the
      // spread's width: the reader keeps the page they are on rather than
      // being sent back to where the screen opened.
      final int at = _controller != null && _controllerEpoch == state.epoch
          ? state.currentPage
          : state.initialPage;
      _controllerEpoch = state.epoch;
      _controllerSpread = _spread;
      _controller = PageController(initialPage: _leafOf(at, state));
    }
    return _controller!;
  }

  // --- leaves ---------------------------------------------------------------
  //
  // The pager turns leaves, not pages. In a window one leaf is one page; on a
  // desk wide enough for it, a leaf is two pages facing each other the way a
  // printed mushaf lies open, the earlier page on the right.
  //
  // Leaves are counted from the first page on show, which for the whole
  // mushaf is page 1 — so the first leaf is pages 1 and 2, Al-Fatiha facing
  // the opening of Al-Baqarah, which is how the mushaf is printed and bound.
  // A surah or a juz read on its own is paired from its own first page
  // instead, so that no half of a leaf is a page the section does not hold.

  /// How many printed pages lie open at once.
  int get _pagesPerLeaf => _spread ? 2 : 1;

  /// The leaf [page] is printed on.
  int _leafOf(int page, MushafState state) =>
      (page - state.firstPage) ~/ _pagesPerLeaf;

  /// The first page of leaf [index]: the right-hand page, the one a mushaf is
  /// read before its neighbour.
  int _firstPageOf(int index, MushafState state) =>
      state.firstPage + index * _pagesPerLeaf;

  /// How many leaves there are to turn through.
  int _leafCount(MushafState state) =>
      (state.visiblePageCount + _pagesPerLeaf - 1) ~/ _pagesPerLeaf;

  // --- the session and the page ---------------------------------------------

  /// Tells the session what the page on show would have it play.
  void _suggestRange(MushafState mushaf) {
    final MushafPage? page = mushaf.pages[mushaf.currentPage];
    if (page == null) return;
    final SessionCubit session = context.read<SessionCubit>();
    final ({AyahRef from, AyahRef to})? range = suggestedRange(
      page: page,
      section: mushaf.section,
      endOfSurah: session.endOfSurah,
    );
    if (range != null) session.suggestRange(range.from, range.to);
  }

  /// The ayah being recited: marked, and — while following — brought on
  /// screen, into another surah or juz if that is where it is.
  void _onUnit(PlaybackUnit? unit) {
    final MushafCubit mushaf = context.read<MushafCubit>();
    if (unit == null) {
      mushaf.clearHighlight();
      return;
    }
    mushaf.highlightAyah(unit.surahNumber, unit.ayahNumber);
    if (_following) mushaf.goToAyah(unit.surahNumber, unit.ayahNumber);
  }

  void _followAgain() {
    setState(() => _following = true);
    final PlaybackUnit? unit = context.read<SessionCubit>().state.currentUnit;
    if (unit != null) {
      context.read<MushafCubit>().goToAyah(unit.surahNumber, unit.ayahNumber);
    }
  }

  Future<void> _openSettings() async {
    final SessionCubit session = context.read<SessionCubit>();
    await SessionSheet.show(context);
    if (!mounted || !session.state.hasPendingChange) return;
    // Put away with changes a running session cannot simply take: they are
    // not left hanging. Start again, carry on, or drop them.
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialog) => AlertDialog(
        title: Text(LocaleKeys.sessionChangedTitle.tr()),
        content: PendingChangeActions(
          onRestart: () {
            session.applyChanges(restart: true);
            Navigator.of(dialog).pop();
          },
          onContinue: () {
            session.applyChanges(restart: false);
            Navigator.of(dialog).pop();
          },
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              session.discardChanges();
              Navigator.of(dialog).pop();
            },
            child: Text(LocaleKeys.sessionDiscardChanges.tr()),
          ),
        ],
      ),
    );
    // Dismissed by tapping outside is the same as dropping them.
    if (session.state.hasPendingChange) session.discardChanges();
  }

  @override
  Widget build(BuildContext context) {
    // Settled before anything below counts a page: a desk wide enough holds
    // two facing pages, a narrower window one. Read from MediaQuery, so
    // dragging the window's edge past that width rebuilds and re-lays the
    // mushaf rather than leaving it as it opened.
    _spread = spreadFits(MediaQuery.sizeOf(context).width);

    return MultiBlocListener(
      listeners: <BlocListener<dynamic, dynamic>>[
        // A face drawn to the other print lays the pages out by its lines.
        BlocListener<SettingsCubit, SettingsState>(
          listenWhen: (SettingsState a, SettingsState b) =>
              a.settings.quranFont.pageFonts != b.settings.quranFont.pageFonts,
          listener: (BuildContext context, SettingsState state) => context
              .read<MushafCubit>()
              .setLayout(MushafLayout.forFont(state.settings.quranFont)),
        ),
        // What "play" would mean follows the page, until the reader chooses.
        BlocListener<MushafCubit, MushafState>(
          listenWhen: (MushafState a, MushafState b) =>
              a.currentPage != b.currentPage ||
              a.epoch != b.epoch ||
              a.pages[b.currentPage] != b.pages[b.currentPage],
          listener: (_, MushafState state) => _suggestRange(state),
        ),
        BlocListener<SessionCubit, SessionState>(
          listenWhen: (SessionState a, SessionState b) =>
              a.ready != b.ready || a.rangeChosen != b.rangeChosen,
          listener: (BuildContext context, _) =>
              _suggestRange(context.read<MushafCubit>().state),
        ),
        BlocListener<SessionCubit, SessionState>(
          listenWhen: (SessionState a, SessionState b) =>
              a.currentUnit?.ref != b.currentUnit?.ref,
          listener: (_, SessionState state) => _onUnit(state.currentUnit),
        ),
        // The veil of a recall round: the ayah being asked back has its words
        // covered until the answering play lifts it.
        BlocListener<SessionCubit, SessionState>(
          listenWhen: (SessionState a, SessionState b) =>
              a.recalling != b.recalling ||
              a.currentUnit?.ref != b.currentUnit?.ref,
          listener: (BuildContext context, SessionState state) => context
              .read<MushafCubit>()
              .veilAyah(state.recalling ? state.currentUnit?.ref : null),
        ),
        // A session that has just started brings its controls up and takes
        // hold of the page again.
        BlocListener<SessionCubit, SessionState>(
          listenWhen: (SessionState a, SessionState b) =>
              a.phase != b.phase && b.phase != SessionPhase.idle,
          listener: (_, SessionState state) => setState(() {
            _chrome = true;
            if (state.phase == SessionPhase.loading) _following = true;
          }),
        ),
        // Reciting to a listener begins with the bar up: it holds the count
        // and the way out.
        BlocListener<SessionCubit, SessionState>(
          listenWhen: (SessionState a, SessionState b) => !a.tasmee && b.tasmee,
          listener: (_, _) => setState(() => _chrome = true),
        ),
        BlocListener<SessionCubit, SessionState>(
          listenWhen: (SessionState a, SessionState b) =>
              a.defaultsSavedAt != b.defaultsSavedAt,
          listener: (BuildContext context, _) =>
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(LocaleKeys.readerSavedAsDefault.tr())),
              ),
        ),
      ],
      child: _scaffold(context),
    );
  }

  Widget _scaffold(BuildContext context) {
    return BlocConsumer<MushafCubit, MushafState>(
      listenWhen: (MushafState a, MushafState b) =>
          a.pageRequest != b.pageRequest && b.pageRequest != null,
      listener: (BuildContext context, MushafState state) {
        final PageController? controller = _controller;
        if (controller == null || !controller.hasClients) return;
        // The leaf the page is printed on: an ayah on the facing page of the
        // spread already on show asks for the leaf it is already on, and
        // nothing moves.
        final int target = _leafOf(state.pageRequest!.page, state);
        // Animate a short hop so the turn is visible; jump a long one. An
        // animation across hundreds of pages would build and load every page
        // it passes, only to show each for a frame.
        if ((target - (controller.page ?? 0)).abs() > _animatedPageSpan) {
          controller.jumpToPage(target);
        } else {
          // A folding leaf needs longer on the air than a slide, or the
          // paper reads as flicked rather than turned.
          final bool paper = _paperTurns(context);
          controller.animateToPage(
            target,
            duration: Duration(milliseconds: paper ? 550 : 350),
            curve: paper ? Curves.easeInOutCubic : Curves.easeInOut,
          );
        }
      },
      buildWhen: (MushafState a, MushafState b) =>
          a.status != b.status ||
          a.currentPage != b.currentPage ||
          a.epoch != b.epoch ||
          a.errorMessage != b.errorMessage,
      builder: (BuildContext context, MushafState state) {
        return Scaffold(
          // No app bar. What it used to say — which surah, which juz, which
          // page — is written in the borders of the page itself, and going
          // back is in the bar a tap brings up, beside the session.
          body: SafeArea(
            child: switch (state.status) {
              LoadStatus.initial || LoadStatus.loading => const Center(
                child: CircularProgressIndicator(),
              ),
              LoadStatus.failure => ErrorView(
                message: state.errorMessage ?? '',
              ),
              // The keyboard turns pages on a desk: a mushaf's next page
              // lies to the left, so the left arrow goes forward. Page Down
              // and Page Up do what they say.
              LoadStatus.ready => CallbackShortcuts(
                bindings: <ShortcutActivator, VoidCallback>{
                  const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                      _turnPage(1),
                  const SingleActivator(LogicalKeyboardKey.pageDown): () =>
                      _turnPage(1),
                  const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                      _turnPage(-1),
                  const SingleActivator(LogicalKeyboardKey.pageUp): () =>
                      _turnPage(-1),
                },
                child: Focus(
                  autofocus: true,
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(child: _pages(context, state)),
                      PositionedDirectional(
                        start: 0,
                        end: 0,
                        bottom: 0,
                        child: DesktopWidth(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              _BackToAyahChip(
                                following: _following,
                                onPressed: _followAgain,
                              ),
                              _ReportHeight(
                                onHeight: (double h) {
                                  if (mounted && h != _barHeight) {
                                    setState(() => _barHeight = h);
                                  }
                                },
                                child: SessionBar(
                                  visible: _chrome,
                                  onOpenSettings: _openSettings,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            },
          ),
        );
      },
    );
  }

  /// One leaf on from here, or one back: what a key does — a page in a
  /// window, both pages of the spread on a desk, the way a hand turns one
  /// leaf of a printed mushaf. The pager clamps the index itself, so the
  /// first and last leaves simply stay.
  void _turnPage(int by) {
    final PageController? controller = _controller;
    if (controller == null || !controller.hasClients) return;
    final int current = controller.page?.round() ?? 0;
    final bool paper = _paperTurns(context);
    controller.animateToPage(
      (current + by).clamp(0, 1 << 20),
      // Longer and softer when the page folds like paper: a key press should
      // still show the whole leaf lifting and landing, not a flick.
      duration: Duration(milliseconds: paper ? 550 : 250),
      curve: paper ? Curves.easeInOutCubic : Curves.easeOut,
    );
  }

  /// Whether the reader has the paper fold turned on.
  static bool _paperTurns(BuildContext context) =>
      context.read<SettingsCubit>().state.settings.pageTurnStyle ==
      PageTurnStyle.paper;

  Widget _pages(BuildContext context, MushafState state) {
    final MushafCubit cubit = context.read<MushafCubit>();
    // How a turned page leaves the screen — folding like paper, or the plain
    // slide. Selected, so flipping the setting re-dresses the pager in place.
    final bool paper =
        context.select<SettingsCubit, PageTurnStyle>(
          (SettingsCubit c) => c.state.settings.pageTurnStyle,
        ) ==
        PageTurnStyle.paper;
    // One more leaf after a surah or a juz: where to go from here.
    final int leaves = _leafCount(state) + (state.section == null ? 0 : 1);
    // A mushaf's next page lies to the left whatever language the interface
    // is in. `reverse: true` puts it there only on an LTR axis — under the
    // Arabic locale's RTL it would flip back to the right — so the axis is
    // pinned to LTR here and each page restores RTL for its own content.
    // On a desk the page is held to a printed page's width, centred; the
    // font is sized to fit that width, so the text stays a reading size
    // however wide the window is. A spread is held to two of those.
    return DesktopWidth(
      maxWidth: _spread ? kDesktopSpreadMaxWidth : kDesktopPageWidth,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification n) {
            // Only the pager's own scrolling, not a tall page scrolling inside
            // it; and only a finger, not the session turning the page.
            if (n.metrics.axis != Axis.horizontal) return false;
            if (n is ScrollStartNotification) _dragging = n.dragDetails != null;
            if (n is ScrollEndNotification) _dragging = false;
            return false;
          },
          child: PageView.builder(
            // Keyed by the run of pages and by how they are laid out, so that
            // another surah or juz — or a window that has just become wide
            // enough for a spread — is a new page view on a new controller
            // rather than the old one re-counted under the reader's thumb.
            key: ValueKey<(int, bool)>((state.epoch, _spread)),
            controller: _controllerFor(state),
            reverse: true,
            // One more leaf after a surah or a juz: where to go from here.
            itemCount: leaves,
            onPageChanged: (int index) {
              if (_dragging && _following) setState(() => _following = false);
              if (index < _leafCount(state)) {
                cubit.onPageChanged(_firstPageOf(index, state));
              }
            },
            itemBuilder: (BuildContext context, int index) {
              Widget leafFor(int i) => Directionality(
                textDirection: TextDirection.rtl,
                child: _leafAt(i, state),
              );
              if (!paper) return leafFor(index);
              return PaperTurn(
                controller: _controllerFor(state),
                index: index,
                spread: _spread,
                // What this leaf lifts off: the next leaf's face, drawn flat
                // beneath it while it turns. The last leaf has none.
                under: index + 1 < leaves ? () => leafFor(index + 1) : null,
                child: leafFor(index),
              );
            },
          ),
        ),
      ),
    );
  }

  /// What the pager draws at [index]: a leaf of the mushaf, or — one past the
  /// last leaf of a surah or a juz — where to go from here.
  Widget _leafAt(int index, MushafState state) {
    if (index >= _leafCount(state)) {
      final Widget end = _SectionEnd(
        section: state.section!,
        onTap: _toggleChrome,
      );
      // Across an open spread that panel would be a box two pages wide: it is
      // held to one page's width, in the middle of the leaf.
      return _spread
          ? Center(
              child: SizedBox(width: kDesktopPageWidth, child: end),
            )
          : end;
    }

    final int first = _firstPageOf(index, state);
    final Widget recto = _PageSlot(
      pageNumber: first,
      onTap: _toggleChrome,
      bottomInset: _bottomInset,
    );
    if (!_spread) return recto;

    final int facing = first + 1;
    // The earlier page is read first, so it is the first child: under RTL a
    // Row lays its children out from the right, which is where a mushaf
    // begins. Stretched, so the fold between them is as tall as the pages.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(child: recto),
        MushafFold(onTap: _toggleChrome),
        Expanded(
          // A section whose last page is a right-hand one has nothing printed
          // facing it.
          child: facing <= state.lastPage
              ? _PageSlot(
                  pageNumber: facing,
                  onTap: _toggleChrome,
                  bottomInset: _bottomInset,
                )
              : MushafBlankPage(onTap: _toggleChrome),
        ),
      ],
    );
  }
}

/// Shown while a session is reciting an ayah the reader has turned away from:
/// one tap goes back to it and takes up following again.
class _BackToAyahChip extends StatelessWidget {
  const _BackToAyahChip({required this.following, required this.onPressed});

  final bool following;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final bool active = context.select<SessionCubit, bool>(
      (SessionCubit c) => c.state.isActive && !c.state.finished,
    );
    if (following || !active) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsetsDirectional.only(bottom: 8.h),
      child: ActionChip(
        avatar: const Icon(Icons.my_location, size: 18),
        label: Text(LocaleKeys.sessionBackToAyah.tr()),
        onPressed: onPressed,
      ),
    );
  }
}

/// The leaf after the last page of a surah or a juz: it is finished, and here
/// are the one after it and the one before.
class _SectionEnd extends StatelessWidget {
  const _SectionEnd({required this.section, required this.onTap});

  final ReadingSection section;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MushafCubit cubit = context.read<MushafCubit>();

    String nameOf(SectionRequest request) => switch (request.kind) {
      SectionKind.surah => LocaleKeys.mushafSurahLabel.tr(
        args: <String>[cubit.surahFor(request.number)?.nameAr ?? ''],
      ),
      SectionKind.juz => LocaleKeys.mushafJuzLabel.tr(
        args: <String>[request.number.toLocalisedString()],
      ),
    };

    final SectionRequest? next = section.next;
    final SectionRequest? previous = section.previous;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: 4.w,
          vertical: 3.h,
        ),
        child: IslamicFrame(
          child: Center(
            child: Padding(
              padding: EdgeInsetsDirectional.all(24.r),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    LocaleKeys.mushafSectionEnd.tr(
                      args: <String>[nameOf(section.request)],
                    ),
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 28.h),
                  if (next != null)
                    FilledButton.icon(
                      onPressed: () => cubit.openSection(next),
                      icon: const Icon(Icons.arrow_forward),
                      label: Text(
                        LocaleKeys.mushafSectionNext.tr(
                          args: <String>[nameOf(next)],
                        ),
                      ),
                    ),
                  if (previous != null) ...<Widget>[
                    SizedBox(height: 12.h),
                    OutlinedButton.icon(
                      onPressed: () => cubit.openSection(previous),
                      icon: const Icon(Icons.arrow_back),
                      label: Text(
                        LocaleKeys.mushafSectionPrevious.tr(
                          args: <String>[nameOf(previous)],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hands [onHeight] its child's height whenever a layout changes it — after
/// the frame, since the caller rebuilds on it.
class _ReportHeight extends SingleChildRenderObjectWidget {
  const _ReportHeight({required this.onHeight, required super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderReportHeight(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderReportHeight renderObject,
  ) => renderObject.onHeight = onHeight;
}

class _RenderReportHeight extends RenderProxyBox {
  _RenderReportHeight(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final double height = size.height;
    if (height == _reported) return;
    _reported = height;
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(height));
  }
}

class _PageSlot extends StatelessWidget {
  const _PageSlot({
    required this.pageNumber,
    required this.onTap,
    required this.bottomInset,
  });

  final int pageNumber;

  /// A tap anywhere on the page: shows or hides the reading bar.
  final VoidCallback onTap;

  /// What the bar covers at the bottom, while it is up.
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MushafCubit, MushafState>(
      buildWhen: (MushafState a, MushafState b) =>
          a.pages[pageNumber] != b.pages[pageNumber] ||
          a.failedPages[pageNumber] != b.failedPages[pageNumber] ||
          a.highlighted != b.highlighted ||
          a.veiled != b.veiled ||
          a.selected != b.selected,
      builder: (BuildContext context, MushafState state) {
        final MushafCubit cubit = context.read<MushafCubit>();
        final MushafPage? page = state.pages[pageNumber];
        final String? failure = state.failedPages[pageNumber];

        if (page == null && failure != null) {
          return ErrorView(
            message: failure,
            onRetry: () => cubit.ensurePage(pageNumber),
          );
        }
        if (page == null) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => cubit.ensurePage(pageNumber),
          );
          return const Center(child: CircularProgressIndicator());
        }

        // The range a session covers — or would — is tinted on the page.
        final ({AyahRef from, AyahRef to})? marked = context
            .select<SessionCubit, ({AyahRef from, AyahRef to})?>(
              (SessionCubit c) => c.state.markedRange,
            );

        // The reader's text size, against the size that fits a printed line
        // to the page exactly.
        final double textScale = context.select<SettingsCubit, double>(
          (SettingsCubit c) =>
              c.state.settings.arabicFontSize /
              AppSettings.defaultArabicFontSize,
        );

        // The reader's mark, where it lands on this page.
        final AyahRef? readingMark = context.select<SettingsCubit, AyahRef?>((
          SettingsCubit c,
        ) {
          final ReadingPosition? mark = c.state.settings.readingMark;
          return mark == null
              ? null
              : AyahRef(mark.surahNumber, mark.ayahNumber);
        });

        final bool ribbon = context.select<SettingsCubit, bool>(
          (SettingsCubit c) => c.state.settings.showReadingRibbon,
        );

        // The ayahs the reader stumbles at, unless they asked for the page
        // without them.
        final Set<AyahRef> stumbled =
            context.select<SettingsCubit, bool>(
              (SettingsCubit c) => c.state.settings.showStumbles,
            )
            ? context.select<SessionCubit, Set<AyahRef>>(
                (SessionCubit c) => c.state.stumbled,
              )
            : const <AyahRef>{};

        // Reciting to a listener: the page is the listener's, shown plainly,
        // and a tap on a word notes a slip at its ayah.
        final bool tasmee = context.select<SessionCubit, bool>(
          (SessionCubit c) => c.state.tasmee,
        );

        final MemorizationView memorizationView = tasmee
            ? MemorizationView.off
            : context.select<SettingsCubit, MemorizationView>(
                (SettingsCubit c) => c.state.settings.memorizationView,
              );

        // Under the QPC V2 face a page is drawn in its own font, and a
        // basmala line in page 1's, whose words it is. Asked for here, where
        // the page is about to be drawn; it is drawn from the bundled face
        // until they are in.
        final bool pageFonts = context.select<SettingsCubit, bool>(
          (SettingsCubit c) => c.state.settings.quranFont.pageFonts,
        );
        Widget view(Set<int> glyphPages) => MushafPageView(
          glyphPages: glyphPages,
          page: page,
          linesPerFullPage: state.linesPerFullPage,
          textScale: textScale,
          highlighted: state.highlighted,
          veiled: state.veiled,
          memorizationView: memorizationView,
          stumbled: stumbled,
          marked: readingMark,
          ribbon: ribbon,
          selected: state.selected,
          isSelected: marked == null
              ? null
              : (Word w) => w.ref.isWithin(marked.from, marked.to),
          isHeldBack: state.section == null
              ? null
              : (Word w) => !state.section!.holds(w.ref),
          onTap: onTap,
          onWordLongPress: (Word word) => _openAyah(context, cubit, word),
          onWordTap: tasmee ? (Word word) => _noteSlip(context, word) : null,
          bottomInset: bottomInset,
        );
        if (!pageFonts) return view(const <int>{});

        final QpcFontService fonts = sl<QpcFontService>();
        final Set<int> wanted = <int>{
          pageNumber,
          if (page.lines.any((PageLine l) => l is BasmalaLine)) 1,
        };
        if (!fonts.loaded.value.containsAll(wanted)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            for (final int p in wanted) {
              unawaited(fonts.ensure(p));
            }
          });
        }
        return ValueListenableBuilder<Set<int>>(
          valueListenable: fonts.loaded,
          builder: (_, Set<int> loaded, _) => view(loaded),
        );
      },
    );
  }

  /// The listener heard a slip at [word]'s ayah. Said back at once, with a
  /// way to take it back: the listener is following a voice, not the
  /// screen, and a tap can land on the wrong word.
  static Future<void> _noteSlip(BuildContext context, Word word) async {
    if (word.isMarker) return;
    final SessionCubit session = context.read<SessionCubit>();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await session.markInTasmee(word.ref);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(
            LocaleKeys.tasmeeNoted.tr(
              args: <String>[word.ayahNumber.toLocalisedString()],
            ),
          ),
          action: SnackBarAction(
            label: LocaleKeys.tasmeeUndo.tr(),
            onPressed: session.undoTasmeeMark,
          ),
        ),
      );
  }

  static Future<void> _openAyah(
    BuildContext context,
    MushafCubit cubit,
    Word word,
  ) async {
    if (word.isMarker) return;
    final Surah? surah = cubit.surahFor(word.surahNumber);
    if (surah == null) return;
    final SessionCubit session = context.read<SessionCubit>();
    final SettingsCubit settings = context.read<SettingsCubit>();
    final AyahRef ayah = word.ref;
    final ReadingPosition? mark = settings.state.settings.readingMark;

    cubit.selectWord(word);
    // Read once and kept; on every later press it is already in hand.
    final List<SimilarRef> similar = <SimilarRef>[
      for (final SimilarAyah s
          in (await sl<MutashabihatRepository>().index()).similarTo(ayah))
        if (cubit.surahFor(s.ref.surah) case final Surah of)
          (ref: s.ref, surah: of),
    ];
    final ({int first, int last})? juz = cubit.juzSpanOf(surah.number);
    if (!context.mounted) return;
    final AyahAction? action = await showModalBottomSheet<AyahAction>(
      context: context,
      // Sized to its entries: six of them, with a chosen range, are more
      // than a sheet's default height holds, and an action out of reach is
      // an action that does not exist.
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AyahActionsSheet(
        ayah: ayah,
        surah: surah,
        canPlay: session.state.reciters.any(
          (r) => r.hasSurah(word.surahNumber),
        ),
        hasChosenRange: session.state.rangeChosen,
        canShare: sl<ShareService>().isSupported,
        isMarked:
            mark != null &&
            mark.surahNumber == ayah.surah &&
            mark.ayahNumber == ayah.ayah,
        isStumbled: session.state.stumbled.contains(ayah),
        similar: similar,
        juzFirst: juz?.first,
        juzLast: juz?.last,
      ),
    );
    if (!cubit.isClosed) cubit.clearSelection();
    if (action == null || session.isClosed) return;

    switch (action) {
      case AyahAction.markHere:
        await settings.markReading(
          ReadingPosition(
            surahNumber: word.surahNumber,
            ayahNumber: word.ayahNumber,
            page: word.page,
            at: DateTime.now(),
          ),
        );
      case AyahAction.unmark:
        await settings.clearReadingMark();
      case AyahAction.share:
        if (context.mounted) await _shareAyah(context, surah, ayah);
      case AyahAction.sharePage:
        final MushafPage? page = cubit.state.pages[word.page];
        if (page != null && context.mounted) {
          await showDialog<void>(
            context: context,
            builder: (_) => PageShareDialog(
              page: page,
              linesPerFullPage: cubit.state.linesPerFullPage,
            ),
          );
        }
      case AyahAction.listenFromHere:
        await session.applyRequest(
          SessionRequest(
            from: ayah,
            to: AyahRef(surah.number, surah.ayahCount),
            preset: SessionPreset.listen,
            autostart: true,
          ),
        );
      case AyahAction.memorizeAlone:
        session.chooseRange(ayah, ayah);
        await session.start();
      case AyahAction.rangeStart:
        session.setStart(ayah);
      case AyahAction.rangeEnd:
        session.setEnd(ayah);
      case AyahAction.clearRange:
        session.clearRange();
      case AyahAction.stumble:
        await session.markStumble(ayah);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(LocaleKeys.mushafStumbleMarked.tr())),
          );
        }
      case AyahAction.clearStumble:
        await session.clearStumble(ayah);
      case AyahAction.similar:
        if (context.mounted) {
          await context.pushNamed<void>(AppRoutes.similarName, extra: ayah);
        }
    }
  }

  /// The ayah's verbatim text, fetched afresh from `quran.db` — never joined
  /// back together from the page's words (A.2 rule 1) — and offered as an
  /// image in the illuminated frame.
  static Future<void> _shareAyah(
    BuildContext context,
    Surah surah,
    AyahRef ayah,
  ) async {
    final List<Ayah>? fetched = (await sl<QuranRepository>().getAyahRange(
      ayah.surah,
      startAyah: ayah.ayah,
      endAyah: ayah.ayah,
    )).fold((_) => null, (List<Ayah> ayahs) => ayahs);
    if (!context.mounted) return;

    if (fetched == null || fetched.length != 1) {
      // Text that cannot be read is reported, never papered over.
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(LocaleKeys.commonError.tr())));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => AyahShareDialog(ayah: fetched.single, surah: surah),
    );
  }
}
