import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/di/injection.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/state/load_status.dart';
import '../../../data/models/surah.dart';
import '../../../data/models/word.dart';
import '../../surah_list/widgets/error_view.dart';
import '../cubit/mushaf_cubit.dart';
import '../cubit/mushaf_page.dart';
import '../cubit/mushaf_state.dart';
import '../mushaf_args.dart';
import '../widgets/ayah_actions_sheet.dart';
import '../widgets/mushaf_page_view.dart';

class MushafScreen extends StatelessWidget {
  const MushafScreen({this.args = const MushafArgs(), super.key});

  final MushafArgs args;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<MushafCubit>(
      create: (_) => sl<MushafCubit>()
        ..init(
          initialAyah: args.initialAyah,
          initialPage: args.initialPage ?? 1,
        ),
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

  /// Whether the bottom bar is showing. It starts hidden: the screen opens on
  /// the page, whole, the way a book opens — and a tap anywhere brings the
  /// controls up, and another puts them away.
  bool _chrome = false;

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

  PageController _controllerFor(MushafState state) =>
      _controller ??= PageController(initialPage: state.initialPage - 1);

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<MushafCubit, MushafState>(
      listenWhen: (MushafState a, MushafState b) =>
          a.pageRequest != b.pageRequest && b.pageRequest != null,
      listener: (BuildContext context, MushafState state) {
        final PageController? controller = _controller;
        if (controller == null || !controller.hasClients) return;
        final int target = state.pageRequest!.page - 1;
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
          a.errorMessage != b.errorMessage,
      builder: (BuildContext context, MushafState state) {
        return Scaffold(
          // No app bar. What it used to say — which surah, which juz, which
          // page — is written in the borders of the page itself now, and its
          // one action, going back, is in the bar a tap brings up.
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
                    child: _ReadingBar(
                      visible: _chrome,
                      page: state.currentPage,
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
      child: PageView.builder(
        controller: _controllerFor(state),
        reverse: true,
        itemCount: state.pageCount,
        onPageChanged: (int index) => cubit.onPageChanged(index + 1),
        itemBuilder: (BuildContext context, int index) => Directionality(
          textDirection: TextDirection.rtl,
          child: _PageSlot(pageNumber: index + 1, onTap: _toggleChrome),
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

        return MushafPageView(
          page: page,
          linesPerFullPage: state.linesPerFullPage,
          highlighted: state.highlighted,
          selected: state.selected,
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

    cubit.selectWord(word);
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => AyahActionsSheet(
        ayah: AyahRef(word.surahNumber, word.ayahNumber),
        surah: surah,
      ),
    );
    if (!cubit.isClosed) cubit.clearSelection();
  }
}

/// The bar a tap brings up from the foot of the page, and a second tap puts
/// away. It slides rather than appears, and while it is away it takes no
/// taps, so the page beneath it is never dead to the touch.
class _ReadingBar extends StatelessWidget {
  const _ReadingBar({required this.visible, required this.page});

  final bool visible;
  final int page;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 1.2),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(12.w, 0, 12.w, 10.h),
            child: Material(
              elevation: 6,
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(18.r),
              child: Padding(
                padding: EdgeInsetsDirectional.symmetric(
                  horizontal: 6.w,
                  vertical: 4.h,
                ),
                child: Row(
                  children: <Widget>[
                    IconButton(
                      tooltip: LocaleKeys.mushafBack.tr(),
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const BackButtonIcon(),
                    ),
                    Expanded(
                      child: Text(
                        LocaleKeys.mushafHintLongPress.tr(),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsetsDirectional.only(end: 12.w),
                      child: Text(
                        LocaleKeys.mushafPage.tr(
                          args: <String>[page.toLocalisedString()],
                        ),
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
