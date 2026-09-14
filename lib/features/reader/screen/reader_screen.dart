import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/injection.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/state/load_status.dart';
import '../../../domain/entities/session_config.dart';
import '../../player/player_args.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../surah_list/widgets/error_view.dart';
import '../cubit/reader_cubit.dart';
import '../cubit/reader_state.dart';
import '../widgets/session_drawer.dart';
import '../widgets/surah_reading_view.dart';

/// The surah, readable, with the session one tap away.
///
/// This is what tapping a surah now opens. The old setup form stood between
/// the reader and the text; here the text is the screen and the session is
/// configured from a drawer if it needs configuring at all.
class ReaderScreen extends StatelessWidget {
  const ReaderScreen({required this.surahNumber, super.key});

  final int surahNumber;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ReaderCubit>(
      create: (_) => sl<ReaderCubit>()..load(surahNumber),
      child: const _ReaderView(),
    );
  }
}

class _ReaderView extends StatefulWidget {
  const _ReaderView();

  @override
  State<_ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends State<_ReaderView> {
  /// Owned by the screen rather than the reading view, so opening and closing
  /// the drawer — which rebuilds the body — does not scroll the page back to
  /// the top.
  final ScrollController _scrollController = ScrollController();

  /// The end drawer is opened through the Scaffold, which needs a key because
  /// the button that opens it is inside that same Scaffold's body.
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double ayahFontSize = context.select<SettingsCubit, double>(
      (SettingsCubit cubit) => cubit.state.settings.arabicFontSize,
    );

    return BlocConsumer<ReaderCubit, ReaderState>(
      listenWhen: (ReaderState a, ReaderState b) =>
          a.defaultsSavedAt != b.defaultsSavedAt,
      listener: (BuildContext context, ReaderState state) {
        if (state.defaultsSavedAt == null) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LocaleKeys.readerSavedAsDefault.tr())),
        );
      },
      builder: (BuildContext context, ReaderState state) {
        return Scaffold(
          key: _scaffoldKey,
          appBar: AppBar(
            title: Text(state.surah?.nameAr ?? ''),
            actions: <Widget>[
              if (state.surah != null)
                IconButton(
                  onPressed: () => context.pushNamed(
                    AppRoutes.progressName,
                    pathParameters: <String, String>{
                      AppRoutes.surahNumberParam: '${state.surah!.number}',
                    },
                  ),
                  tooltip: LocaleKeys.progressTitle.tr(),
                  icon: const Icon(Icons.insights_outlined),
                ),
            ],
          ),
          // Scaffold.endDrawer, so it slides in from the trailing edge: the
          // left in RTL, the right in LTR. Directionality handles the side, so
          // nothing here mirrors anything by hand.
          endDrawer: state.status.isReady ? SessionDrawer(state: state) : null,
          body: switch (state.status) {
            LoadStatus.initial || LoadStatus.loading => const Center(
              child: CircularProgressIndicator(),
            ),
            LoadStatus.failure => ErrorView(message: state.errorMessage ?? ''),
            LoadStatus.ready => _ReaderBody(
              state: state,
              fontSize: ayahFontSize,
              scrollController: _scrollController,
              onOpenDrawer: () =>
                  _scaffoldKey.currentState?.openEndDrawer(),
            ),
          },
        );
      },
    );
  }
}

class _ReaderBody extends StatelessWidget {
  const _ReaderBody({
    required this.state,
    required this.fontSize,
    required this.scrollController,
    required this.onOpenDrawer,
  });

  final ReaderState state;
  final double fontSize;
  final ScrollController scrollController;
  final VoidCallback onOpenDrawer;

  @override
  Widget build(BuildContext context) {
    final ReaderCubit cubit = context.read<ReaderCubit>();

    return Column(
      children: <Widget>[
        Expanded(
          child: SurahReadingView(
            surah: state.surah!,
            ayahs: state.ayahs,
            fontSize: fontSize,
            bismillahText: state.bismillahText,
            isSelected: state.isSelected,
            onAyahTap: cubit.tapAyah,
            scrollController: scrollController,
          ),
        ),
        const Divider(height: 1),
        _BottomBar(state: state, onOpenDrawer: onOpenDrawer),
      ],
    );
  }
}

/// Pinned above the safe area: what will play, and the button that plays it.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.state, required this.onOpenDrawer});

  final ReaderState state;
  final VoidCallback onOpenDrawer;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ReaderCubit cubit = context.read<ReaderCubit>();

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: 16.w,
          vertical: 12.h,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    _selectionSummary(state),
                    style: theme.textTheme.titleSmall,
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    state.isWholeSurahSelected
                        ? LocaleKeys.readerTapToSelect.tr()
                        : LocaleKeys.readerSessionSettings.tr(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            SizedBox(width: 12.w),
            IconButton.filledTonal(
              onPressed: onOpenDrawer,
              tooltip: LocaleKeys.readerSessionSettings.tr(),
              icon: const Icon(Icons.tune),
            ),
            SizedBox(width: 8.w),
            FilledButton.icon(
              onPressed: state.canStart
                  ? () => _start(context, cubit, state)
                  : null,
              icon: const Icon(Icons.play_arrow),
              label: Text(LocaleKeys.sessionSetupStart.tr()),
            ),
          ],
        ),
      ),
    );
  }

  static void _start(
    BuildContext context,
    ReaderCubit cubit,
    ReaderState state,
  ) {
    // Recorded before navigating so "last used" survives even if the reader
    // never comes back to this screen.
    cubit.rememberStartedRange();

    context.pushNamed(
      AppRoutes.playerName,
      extra: PlayerArgs(
        plan: state.plan!,
        surah: state.surah!,
        reciter: state.reciter!,
        ayahs: state.ayahs,
      ),
    );
  }

  /// «السورة كاملة», «الآية ٣» or «الآيات ١ - ٧» — whichever the selection
  /// actually is, in the locale's own numerals.
  static String _selectionSummary(ReaderState state) {
    final SessionConfig? config = state.config;
    if (config == null) return '';
    if (state.isWholeSurahSelected) return LocaleKeys.readerWholeSurah.tr();
    if (config.startAyah == config.endAyah) {
      return LocaleKeys.readerSelectionSingle.tr(
        args: <String>[config.startAyah.toLocalisedString()],
      );
    }
    return LocaleKeys.commonAyahRange.tr(
      args: <String>[
        config.startAyah.toLocalisedString(),
        config.endAyah.toLocalisedString(),
      ],
    );
  }
}
