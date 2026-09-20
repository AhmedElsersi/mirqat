import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/di/injection.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/state/load_status.dart';
import '../../../data/models/app_settings.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../home/cubit/home_index_cubit.dart';
import '../../home/cubit/home_index_state.dart';
import '../../home/widgets/juz_widgets.dart';
import '../../mushaf/mushaf_args.dart';
import '../../mushaf/reading_section.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../settings/cubit/settings_state.dart';
import '../cubit/surah_list_cubit.dart';
import '../cubit/surah_list_state.dart';
import '../widgets/error_view.dart';
import '../widgets/surah_row.dart';
import '../widgets/surah_tile.dart';

/// Home: the surahs and the ajzaa, side by side as two tabs.
///
/// How they are drawn — a list, a grid, or not at all because the app opens
/// straight onto the mushaf — is a setting, not a button here: it is chosen
/// once and lived with, and three icons for it crowded out the two things
/// this bar is for, the way back to where you were and the settings.
class SurahListScreen extends StatelessWidget {
  const SurahListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: <BlocProvider<dynamic>>[
        BlocProvider<SurahListCubit>(
          create: (_) => sl<SurahListCubit>()..load(),
        ),
        BlocProvider<HomeIndexCubit>(
          create: (_) => sl<HomeIndexCubit>()..load(),
        ),
      ],
      child: const _SurahListView(),
    );
  }
}

class _SurahListView extends StatefulWidget {
  const _SurahListView();

  @override
  State<_SurahListView> createState() => _SurahListViewState();
}

class _SurahListViewState extends State<_SurahListView> {
  final ScrollController _surahScroll = ScrollController();
  final ScrollController _juzScroll = ScrollController();

  /// Whether this launch has already decided how to open. It is decided
  /// exactly once, the first moment the settings and the history are both
  /// known — and never again. Coming *back* to the index from the mushaf must
  /// stay on the index; and choosing "mushaf" in Settings must not throw the
  /// mushaf open over the Settings screen, which is what re-deciding on every
  /// change of the setting did.
  bool _launchDecided = false;

  @override
  void dispose() {
    _surahScroll.dispose();
    _juzScroll.dispose();
    super.dispose();
  }

  /// In mushaf mode the app opens on the last page read, with this screen
  /// underneath it as the index — so "back" from the mushaf lands here, and
  /// there is always a way to another surah, the history and the settings.
  void _decideLaunch(HomeViewMode mode, HomeIndexState index) {
    if (_launchDecided || !index.loaded) return;
    _launchDecided = true;
    final int? page = launchPage(mode: mode, last: index.last?.position);
    if (page == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openMushaf(context, page: page);
    });
  }

  @override
  Widget build(BuildContext context) {
    final SettingsState settings = context.watch<SettingsCubit>().state;
    final HomeViewMode viewMode = settings.settings.homeViewMode;
    final HomeIndexState index = context.watch<HomeIndexCubit>().state;
    if (settings.status.isReady) _decideLaunch(viewMode, index);

    // The mushaf has no list shape of its own; its index is the plain list.
    final bool grid = viewMode == HomeViewMode.grid;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(LocaleKeys.appName.tr()),
          actions: <Widget>[
            IconButton(
              onPressed: () async {
                await context.pushNamed<void>(AppRoutes.historyName);
                if (context.mounted) {
                  await context.read<HomeIndexCubit>().refreshHistory();
                }
              },
              tooltip: LocaleKeys.homeHistory.tr(),
              icon: const Icon(Icons.history),
            ),
            IconButton(
              onPressed: () => context.pushNamed(AppRoutes.settingsName),
              tooltip: LocaleKeys.settingsTitle.tr(),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
          bottom: TabBar(
            tabs: <Widget>[
              Tab(text: LocaleKeys.homeTabSurahs.tr()),
              Tab(text: LocaleKeys.homeTabAjzaa.tr()),
            ],
          ),
        ),
        body: Column(
          children: <Widget>[
            if (index.last case final PlaceItem last)
              _ContinueCard(
                place: last,
                onTap: () => _openMushaf(context, page: last.position.page),
              ),
            Expanded(
              child: TabBarView(
                children: <Widget>[
                  _surahs(context, grid: grid, mode: viewMode),
                  _ajzaa(context, index, grid: grid, mode: viewMode),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _surahs(
    BuildContext context, {
    required bool grid,
    required HomeViewMode mode,
  }) => BlocBuilder<SurahListCubit, SurahListState>(
    builder: (BuildContext context, SurahListState state) {
      if (state.status.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (state.status.isFailure) {
        return ErrorView(
          message: state.errorMessage ?? '',
          onRetry: () => context.read<SurahListCubit>().load(),
        );
      }
      if (state.items.isEmpty) {
        return Center(child: Text(LocaleKeys.surahListEmpty.tr()));
      }

      void open(SurahListItem item) =>
          _openSurah(context, item, inMushaf: mode == HomeViewMode.mushaf);

      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        // Cross-fade in place. A slide would read as navigation, and this
        // is the same content in a different shape.
        child: grid
            ? _SurahGrid(
                key: const ValueKey<String>('grid'),
                items: state.items,
                controller: _surahScroll,
                onOpen: open,
              )
            : _SurahList(
                key: const ValueKey<String>('list'),
                items: state.items,
                controller: _surahScroll,
                onOpen: open,
              ),
      );
    },
  );

  Widget _ajzaa(
    BuildContext context,
    HomeIndexState index, {
    required bool grid,
    required HomeViewMode mode,
  }) {
    if (!index.loaded) return const Center(child: CircularProgressIndicator());

    // The same choice a surah makes: the mushaf at the juz's first page, or
    // that juz on its own.
    void open(JuzItem juz) => mode == HomeViewMode.mushaf
        ? _openMushaf(context, page: juz.info.page)
        : _openMushaf(context, section: SectionRequest.juz(juz.info.number));

    if (!grid) {
      return ListView.separated(
        controller: _juzScroll,
        padding: EdgeInsetsDirectional.only(bottom: 24.h),
        itemCount: index.ajzaa.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (BuildContext context, int i) =>
            JuzRow(item: index.ajzaa[i], onTap: () => open(index.ajzaa[i])),
      );
    }

    final bool wide =
        MediaQuery.sizeOf(context).width >= AppConstants.tabletBreakpoint;
    return GridView.builder(
      controller: _juzScroll,
      padding: EdgeInsetsDirectional.all(12.r),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: wide ? 3 : 2,
        mainAxisSpacing: 12.r,
        crossAxisSpacing: 12.r,
        mainAxisExtent:
            // Logical pixels, not `.h`: the card's content does not shrink on
            // a short screen, so neither may the room it is given — scaled to
            // the screen's height it overflowed on anything short and wide.
            150 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6),
      ),
      itemCount: index.ajzaa.length,
      itemBuilder: (BuildContext context, int i) =>
          JuzTile(item: index.ajzaa[i], onTap: () => open(index.ajzaa[i])),
    );
  }
}

/// "Continue reading": the last place, one tap away, above both tabs.
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.place, required this.onTap});

  final PlaceItem place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool arabic = context.locale.languageCode == 'ar';
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(12.w, 10.h, 12.w, 4.h),
      child: Material(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(16.r),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsetsDirectional.symmetric(
              horizontal: 16.w,
              vertical: 12.h,
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.bookmark, color: theme.colorScheme.secondary),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        LocaleKeys.homeContinueReading.tr(),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onPrimary.withValues(
                            alpha: 0.8,
                          ),
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        LocaleKeys.homePlace.tr(
                          args: <String>[
                            arabic ? place.surah.nameAr : place.surah.nameEn,
                            place.position.ayahNumber.toLocalisedString(),
                            place.position.page.toLocalisedString(),
                          ],
                        ),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: theme.colorScheme.onPrimary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SurahList extends StatelessWidget {
  const _SurahList({
    required this.items,
    required this.controller,
    required this.onOpen,
    super.key,
  });

  final List<SurahListItem> items;
  final ScrollController controller;
  final ValueChanged<SurahListItem> onOpen;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      controller: controller,
      padding: EdgeInsetsDirectional.only(bottom: 24.h),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        final SurahListItem item = items[index];
        return SurahRow(
          item: item,
          onTap: () => onOpen(item),
          onProgressTap: () => _openProgress(context, item),
        );
      },
    );
  }
}

class _SurahGrid extends StatelessWidget {
  const _SurahGrid({
    required this.items,
    required this.controller,
    required this.onOpen,
    super.key,
  });

  final List<SurahListItem> items;
  final ScrollController controller;
  final ValueChanged<SurahListItem> onOpen;

  @override
  Widget build(BuildContext context) {
    // Two columns on a phone, three from the tablet breakpoint up. Measured
    // against the real window, not the ScreenUtil design width, because the
    // question is how much room there actually is.
    final bool wide =
        MediaQuery.sizeOf(context).width >= AppConstants.tabletBreakpoint;

    return GridView.builder(
      controller: controller,
      padding: EdgeInsetsDirectional.all(12.r),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: wide ? 3 : 2,
        mainAxisSpacing: 12.r,
        crossAxisSpacing: 12.r,
        // A fixed extent rather than an aspect ratio: every tile is then the
        // same height whatever its name's length, and the tallest content
        // decides that height once instead of per row. Scales with the text
        // scale so a large system font has somewhere to go.
        mainAxisExtent:
            180.h * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6),
      ),
      itemCount: items.length,
      itemBuilder: (BuildContext context, int index) {
        final SurahListItem item = items[index];
        return SurahTile(item: item, onTap: () => onOpen(item));
      },
    );
  }
}

/// Opens a surah: in the mushaf view, the mushaf at the page it begins on; in
/// list or grid, that surah on its own. The "continue" card is brought up to
/// date on the way back.
Future<void> _openSurah(
  BuildContext context,
  SurahListItem item, {
  required bool inMushaf,
}) async {
  if (!inMushaf) {
    return _openMushaf(
      context,
      section: SectionRequest.surah(item.surah.number),
    );
  }
  final int? page = await context.read<HomeIndexCubit>().pageOfSurah(
    item.surah.number,
  );
  if (context.mounted) await _openMushaf(context, page: page);
}

/// Opens the reading view: the whole mushaf at [page], or one [section] of
/// it. The mushaf writes down where the reader gets to; this only reads it
/// back when they return.
Future<void> _openMushaf(
  BuildContext context, {
  int? page,
  SectionRequest? section,
}) async {
  final HomeIndexCubit index = context.read<HomeIndexCubit>();
  await context.pushNamed<void>(
    AppRoutes.mushafName,
    extra: MushafArgs(initialPage: page, section: section),
  );
  await index.refreshHistory();
}

void _openProgress(BuildContext context, SurahListItem item) =>
    context.pushNamed(
      AppRoutes.progressName,
      pathParameters: <String, String>{
        AppRoutes.surahNumberParam: '${item.surah.number}',
      },
    );
