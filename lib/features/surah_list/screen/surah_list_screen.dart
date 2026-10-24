import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/desktop.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/state/load_status.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/panel.dart';
import '../../../data/models/app_settings.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../home/cubit/home_index_cubit.dart';
import '../../home/cubit/home_index_state.dart';
import '../../home/widgets/juz_widgets.dart';
import '../../mushaf/mushaf_args.dart';
import '../../mushaf/reading_section.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../cubit/surah_list_cubit.dart';
import '../cubit/surah_list_state.dart';
import '../widgets/error_view.dart';
import '../widgets/surah_row.dart';
import '../widgets/surah_tile.dart';

/// The Mushaf tab: the way into the text — search, where the reader stopped,
/// and the surahs and ajzaa side by side as two tabs.
///
/// How they are drawn — a list, a grid, or not at all because the app opens
/// straight onto the mushaf — is a setting, not a button here. The cubits it
/// reads are the home shell's, shared with the other tabs.
class SurahListScreen extends StatefulWidget {
  const SurahListScreen({this.place, this.onOpenPlace, super.key});

  /// Where the reader stopped, and how to go back there.
  final PlaceItem? place;
  final VoidCallback? onOpenPlace;

  @override
  State<SurahListScreen> createState() => _SurahListScreenState();
}

class _SurahListScreenState extends State<SurahListScreen> {
  final ScrollController _surahScroll = ScrollController();
  final ScrollController _juzScroll = ScrollController();
  final ScrollController _hizbScroll = ScrollController();

  @override
  void dispose() {
    _surahScroll.dispose();
    _juzScroll.dispose();
    _hizbScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final HomeViewMode viewMode = context.select<SettingsCubit, HomeViewMode>(
      (SettingsCubit c) => c.state.settings.homeViewMode,
    );
    final bool marked = context.select<SettingsCubit, bool>(
      (SettingsCubit c) => c.state.settings.readingMark != null,
    );
    final HomeIndexState index = context.watch<HomeIndexCubit>().state;
    final PlaceItem? last = widget.place;

    // The mushaf has no list shape of its own; its index is the plain list.
    final bool grid = viewMode == HomeViewMode.grid;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: DesktopWidth(
            child: Column(
              children: <Widget>[
                Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(16.w, 8.h, 12.w, 0),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          LocaleKeys.tabsMushaf.tr(),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton.outlined(
                        onPressed: () async {
                          await context.pushNamed<void>(AppRoutes.historyName);
                          if (context.mounted) {
                            await context
                                .read<HomeIndexCubit>()
                                .refreshHistory();
                          }
                        },
                        tooltip: LocaleKeys.homeHistory.tr(),
                        icon: const Icon(Icons.history),
                      ),
                    ],
                  ),
                ),
                _SearchField(
                  onTap: () => context.pushNamed(AppRoutes.searchName),
                ),
                if (last != null)
                  _ContinueCard(
                    place: last,
                    // The icon says which it is: a mark the reader set, or
                    // the page the app remembered.
                    icon: marked ? Icons.bookmark_added : Icons.bookmark,
                    onTap: widget.onOpenPlace ?? () {},
                  ),
                const _SegmentedTabs(),
                Expanded(
                  child: TabBarView(
                    children: <Widget>[
                      _surahs(context, grid: grid, mode: viewMode),
                      _ajzaa(context, index, grid: grid, mode: viewMode),
                      _ajzaa(
                        context,
                        index,
                        grid: grid,
                        mode: viewMode,
                        ahzab: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
    bool ahzab = false,
  }) {
    if (!index.loaded) return const Center(child: CircularProgressIndicator());

    final List<JuzItem> parts = ahzab ? index.ahzab : index.ajzaa;
    final ScrollController scroll = ahzab ? _hizbScroll : _juzScroll;
    final String nameKey = ahzab
        ? LocaleKeys.homeHizbName
        : LocaleKeys.homeJuzName;

    // The same choice a surah makes: the mushaf at the part's first page, or
    // that juz on its own. A hizb is not a reading section the app knows, so
    // it always opens the mushaf where it begins.
    void open(JuzItem part) => ahzab || mode == HomeViewMode.mushaf
        ? openMushaf(context, page: part.info.page)
        : openMushaf(context, section: SectionRequest.juz(part.info.number));

    if (!grid) {
      return ListCardView(
        controller: scroll,
        itemCount: parts.length,
        itemBuilder: (BuildContext context, int i) => JuzRow(
          item: parts[i],
          nameKey: nameKey,
          onTap: () => open(parts[i]),
        ),
      );
    }

    final bool wide =
        MediaQuery.sizeOf(context).width >= AppConstants.tabletBreakpoint;
    return GridView.builder(
      controller: scroll,
      padding: EdgeInsetsDirectional.all(12.r),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: wide ? 3 : 2,
        mainAxisSpacing: 12.r,
        crossAxisSpacing: 12.r,
        mainAxisExtent:
            // Not `.h`: the card's content does not shrink on a short
            // screen, so neither may the room it is given — scaled to the
            // screen's height it overflowed on anything short and wide. But
            // its content *is* scaled by width (`.w`, `.r`), so the room grows
            // with that and never shrinks below what a phone needs.
            150 *
            math.max(1, ScreenUtil().scaleWidth) *
            MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6),
      ),
      itemCount: parts.length,
      itemBuilder: (BuildContext context, int i) => JuzTile(
        item: parts[i],
        nameKey: nameKey,
        onTap: () => open(parts[i]),
      ),
    );
  }
}

/// "Continue reading": the last place, one tap away, above both tabs.
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.place,
    required this.icon,
    required this.onTap,
  });

  final PlaceItem place;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool arabic = context.locale.languageCode == 'ar';
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(16.w, 12.h, 16.w, 0),
      child: Material(
        color: AppColors.forest,
        borderRadius: BorderRadius.circular(18.r),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsetsDirectional.all(16.r),
            child: Row(
              children: <Widget>[
                Icon(icon, color: AppColors.gold),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        LocaleKeys.homeContinueAt.tr(
                          args: <String>[
                            arabic ? place.surah.nameAr : place.surah.nameEn,
                            place.position.ayahNumber.toLocalisedString(),
                          ],
                        ),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: AppColors.cream,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        LocaleKeys.homePage.tr(
                          args: <String>[
                            place.position.page.toLocalisedString(),
                          ],
                        ),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.cream.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                // An arrow, not a chevron: this one goes somewhere else.
                const Icon(Icons.arrow_forward, color: AppColors.cream),
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
    return ListCardView(
      controller: controller,
      itemCount: items.length,
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
    return openMushaf(
      context,
      section: SectionRequest.surah(item.surah.number),
    );
  }
  final int? page = await context.read<HomeIndexCubit>().pageOfSurah(
    item.surah.number,
  );
  if (context.mounted) await openMushaf(context, page: page);
}

/// Opens the reading view: the whole mushaf at [page], or one [section] of
/// it. The mushaf writes down where the reader gets to; this only reads it
/// back when they return.
Future<void> openMushaf(
  BuildContext context, {
  int? page,
  SectionRequest? section,
  bool tasmee = false,
}) async {
  final HomeIndexCubit index = context.read<HomeIndexCubit>();
  await context.pushNamed<void>(
    AppRoutes.mushafName,
    extra: MushafArgs(initialPage: page, section: section, tasmee: tasmee),
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

/// Search, as a field: in an index of 114 surahs and 604 pages it is the
/// quickest way in, so it is shown, not hidden behind an icon.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(16.w, 12.h, 16.w, 0),
      child: Material(
        color: theme.colorScheme.surface,
        shape: StadiumBorder(
          side: BorderSide(color: theme.colorScheme.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 50.r,
            child: Row(
              children: <Widget>[
                SizedBox(width: 14.w),
                Icon(Icons.search, color: theme.colorScheme.onSurfaceVariant),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    LocaleKeys.searchHint.tr(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The surahs | ajzaa switch, drawn as a segmented control.
class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(16.w, 14.h, 16.w, 8.h),
      child: Container(
        padding: EdgeInsetsDirectional.all(4.r),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14.r),
        ),
        child: TabBar(
          dividerHeight: 0,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(10.r),
          ),
          labelColor: theme.colorScheme.onSurface,
          unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
          labelStyle: theme.textTheme.titleSmall,
          tabs: <Widget>[
            Tab(height: 40.r, text: LocaleKeys.homeTabSurahs.tr()),
            Tab(height: 40.r, text: LocaleKeys.homeTabAjzaa.tr()),
            Tab(height: 40.r, text: LocaleKeys.homeTabAhzab.tr()),
          ],
        ),
      ),
    );
  }
}
