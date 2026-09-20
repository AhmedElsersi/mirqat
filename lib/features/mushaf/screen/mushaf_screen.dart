import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/di/injection.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../../domain/entities/playback_unit.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/state/load_status.dart';
import '../../../core/widgets/islamic_frame.dart';
import '../../../data/models/surah.dart';
import '../../../data/models/word.dart';
import '../../session/cubit/session_cubit.dart';
import '../../session/cubit/session_state.dart';
import '../../session/default_range.dart';
import '../../session/widgets/session_bar.dart';
import '../../session/widgets/session_sheet.dart';
import '../../surah_list/widgets/error_view.dart';
import '../cubit/mushaf_cubit.dart';
import '../cubit/mushaf_page.dart';
import '../cubit/mushaf_state.dart';
import '../mushaf_args.dart';
import '../reading_section.dart';
import '../widgets/ayah_actions_sheet.dart';
import '../widgets/mushaf_page_view.dart';

class MushafScreen extends StatelessWidget {
  const MushafScreen({this.args = const MushafArgs(), super.key});

  final MushafArgs args;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: <BlocProvider<dynamic>>[
        BlocProvider<MushafCubit>(
          create: (_) => sl<MushafCubit>()
            ..init(
              initialAyah: args.initialAyah,
              initialPage: args.initialPage ?? 1,
              section: args.section,
            ),
        ),
        // The session belongs to the reading screen: it plays over this text
        // and ends when the screen is left.
        BlocProvider<SessionCubit>(create: (_) => sl<SessionCubit>()..load()),
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

  /// Whether the bottom bar is showing. It starts hidden: the screen opens on
  /// the page, whole, the way a book opens — and a tap anywhere brings the
  /// controls up, and another puts them away.
  bool _chrome = false;

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
    if (_controller == null || _controllerEpoch != state.epoch) {
      final PageController? old = _controller;
      // Disposed after the frame: the old page view is still attached to it
      // until this build has replaced that view.
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
      _controllerEpoch = state.epoch;
      _controller = PageController(
        initialPage: state.initialPage - state.firstPage,
      );
    }
    return _controller!;
  }

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
    return MultiBlocListener(
      listeners: <BlocListener<dynamic, dynamic>>[
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
        final int target = state.pageRequest!.page - state.firstPage;
        // Animate a short hop so the turn is visible; jump a long one. An
        // animation across hundreds of pages would build and load every page
        // it passes, only to show each for a frame.
        if ((target - (controller.page ?? 0)).abs() > _animatedPageSpan) {
          controller.jumpToPage(target);
        } else {
          controller.animateToPage(
            target,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
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
              LoadStatus.ready => Stack(
                children: <Widget>[
                  Positioned.fill(child: _pages(context, state)),
                  PositionedDirectional(
                    start: 0,
                    end: 0,
                    bottom: 0,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _BackToAyahChip(
                          following: _following,
                          onPressed: _followAgain,
                        ),
                        SessionBar(
                          visible: _chrome,
                          onOpenSettings: _openSettings,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            },
          ),
        );
      },
    );
  }

  Widget _pages(BuildContext context, MushafState state) {
    final MushafCubit cubit = context.read<MushafCubit>();
    // A mushaf's next page lies to the left whatever language the interface
    // is in. `reverse: true` puts it there only on an LTR axis — under the
    // Arabic locale's RTL it would flip back to the right — so the axis is
    // pinned to LTR here and each page restores RTL for its own content.
    return Directionality(
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
          // Keyed by the run of pages, so that another surah or juz is a new
          // page view on a new controller rather than the old one re-counted
          // under the reader's thumb.
          key: ValueKey<int>(state.epoch),
          controller: _controllerFor(state),
          reverse: true,
          // One more leaf after a surah or a juz: where to go from here.
          itemCount: state.visiblePageCount + (state.section == null ? 0 : 1),
          onPageChanged: (int index) {
            if (_dragging && _following) setState(() => _following = false);
            if (index < state.visiblePageCount) {
              cubit.onPageChanged(state.firstPage + index);
            }
          },
          itemBuilder: (BuildContext context, int index) => Directionality(
            textDirection: TextDirection.rtl,
            child: index < state.visiblePageCount
                ? _PageSlot(
                    pageNumber: state.firstPage + index,
                    onTap: _toggleChrome,
                  )
                : _SectionEnd(section: state.section!, onTap: _toggleChrome),
          ),
        ),
      ),
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

class _PageSlot extends StatelessWidget {
  const _PageSlot({required this.pageNumber, required this.onTap});

  final int pageNumber;

  /// A tap anywhere on the page: shows or hides the reading bar.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MushafCubit, MushafState>(
      buildWhen: (MushafState a, MushafState b) =>
          a.pages[pageNumber] != b.pages[pageNumber] ||
          a.failedPages[pageNumber] != b.failedPages[pageNumber] ||
          a.highlighted != b.highlighted ||
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

        return MushafPageView(
          page: page,
          linesPerFullPage: state.linesPerFullPage,
          highlighted: state.highlighted,
          selected: state.selected,
          isSelected: marked == null
              ? null
              : (Word w) => w.ref.isWithin(marked.from, marked.to),
          isHeldBack: state.section == null
              ? null
              : (Word w) => !state.section!.holds(w.ref),
          onTap: onTap,
          onWordLongPress: (Word word) => _openAyah(context, cubit, word),
        );
      },
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
    final AyahRef ayah = word.ref;

    cubit.selectWord(word);
    final AyahAction? action = await showModalBottomSheet<AyahAction>(
      context: context,
      builder: (_) => AyahActionsSheet(
        ayah: ayah,
        surah: surah,
        canPlay: session.state.reciters.any(
          (r) => r.hasSurah(word.surahNumber),
        ),
        hasChosenRange: session.state.rangeChosen,
      ),
    );
    if (!cubit.isClosed) cubit.clearSelection();
    if (action == null || session.isClosed) return;

    switch (action) {
      case AyahAction.playFromHere:
        session.chooseRange(ayah, AyahRef(surah.number, surah.ayahCount));
        await session.start();
      case AyahAction.memorizeAlone:
        session.chooseRange(ayah, ayah);
        await session.start();
      case AyahAction.rangeStart:
        session.setStart(ayah);
      case AyahAction.rangeEnd:
        session.setEnd(ayah);
      case AyahAction.clearRange:
        session.clearRange();
    }
  }
}
