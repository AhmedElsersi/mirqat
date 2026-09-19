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
      create: (_) => sl<MushafCubit>()..init(initialAyah: args.initialAyah),
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

class _MushafViewState extends State<MushafView> {
  /// The furthest [MushafCubit.goToAyah] animates rather than jumps.
  static const int _animatedPageSpan = 2;

  PageController? _controller;

  @override
  void dispose() {
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
          appBar: AppBar(title: Text(LocaleKeys.mushafTitle.tr())),
          body: switch (state.status) {
            LoadStatus.initial || LoadStatus.loading => const Center(
              child: CircularProgressIndicator(),
            ),
            LoadStatus.failure => ErrorView(message: state.errorMessage ?? ''),
            LoadStatus.ready => Column(
              children: <Widget>[
                Expanded(child: _pages(context, state)),
                // Above the system gesture bar, not underneath it.
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsetsDirectional.only(top: 4.h, bottom: 8.h),
                    child: Text(
                      LocaleKeys.mushafPage.tr(
                        args: <String>[state.currentPage.toLocalisedString()],
                      ),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ),
              ],
            ),
          },
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
          child: _PageSlot(pageNumber: index + 1),
        ),
      ),
    );
  }
}

class _PageSlot extends StatelessWidget {
  const _PageSlot({required this.pageNumber});

  final int pageNumber;

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
          onWordTap: (Word word) => _openAyah(context, cubit, word),
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
