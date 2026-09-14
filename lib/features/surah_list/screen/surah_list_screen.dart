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
import '../../settings/cubit/settings_cubit.dart';
import '../cubit/surah_list_cubit.dart';
import '../cubit/surah_list_state.dart';
import '../widgets/error_view.dart';
import '../widgets/surah_row.dart';
import '../widgets/surah_tile.dart';

/// Home. Lists exactly what the catalog holds — four surahs at the moment,
/// which is correct rather than a gap to fill with placeholders.
class SurahListScreen extends StatelessWidget {
  const SurahListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<SurahListCubit>(
      create: (_) => sl<SurahListCubit>()..load(),
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
  /// Shared by both layouts, so flipping between them keeps the reader roughly
  /// where they were instead of jumping to the top. The offsets are not
  /// identical — a grid is shorter than the same list — so it is clamped to
  /// each layout's own extent on the first frame after the switch.
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final HomeViewMode viewMode = context.select<SettingsCubit, HomeViewMode>(
      (SettingsCubit cubit) => cubit.state.settings.homeViewMode,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(LocaleKeys.appName.tr()),
        actions: <Widget>[
          _ViewModeToggle(mode: viewMode),
          IconButton(
            onPressed: () => context.pushNamed(AppRoutes.settingsName),
            tooltip: LocaleKeys.settingsTitle.tr(),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: BlocBuilder<SurahListCubit, SurahListState>(
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

          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            // Cross-fade in place. A slide would read as navigation, and this
            // is the same content in a different shape.
            child: switch (viewMode) {
              HomeViewMode.list => _SurahList(
                key: const ValueKey<String>('list'),
                items: state.items,
                controller: _scrollController,
              ),
              HomeViewMode.grid => _SurahGrid(
                key: const ValueKey<String>('grid'),
                items: state.items,
                controller: _scrollController,
              ),
            },
          );
        },
      ),
    );
  }
}

/// One button, showing the layout it switches *to*.
class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({required this.mode});

  final HomeViewMode mode;

  @override
  Widget build(BuildContext context) {
    final bool isList = mode == HomeViewMode.list;

    return IconButton(
      onPressed: () => context.read<SettingsCubit>().setHomeViewMode(
        isList ? HomeViewMode.grid : HomeViewMode.list,
      ),
      tooltip: isList
          ? LocaleKeys.settingsHomeViewGrid.tr()
          : LocaleKeys.settingsHomeViewList.tr(),
      icon: Icon(isList ? Icons.grid_view_outlined : Icons.view_list_outlined),
    );
  }
}

class _SurahList extends StatelessWidget {
  const _SurahList({required this.items, required this.controller, super.key});

  final List<SurahListItem> items;
  final ScrollController controller;

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
          onTap: () => _openReader(context, item),
          onProgressTap: () => _openProgress(context, item),
        );
      },
    );
  }
}

class _SurahGrid extends StatelessWidget {
  const _SurahGrid({required this.items, required this.controller, super.key});

  final List<SurahListItem> items;
  final ScrollController controller;

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
        return SurahTile(
          item: item,
          onTap: () => _openReader(context, item),
        );
      },
    );
  }
}

void _openReader(BuildContext context, SurahListItem item) =>
    context.pushNamed(
      AppRoutes.readerName,
      pathParameters: <String, String>{
        AppRoutes.surahNumberParam: '${item.surah.number}',
      },
    );

void _openProgress(BuildContext context, SurahListItem item) =>
    context.pushNamed(
      AppRoutes.progressName,
      pathParameters: <String, String>{
        AppRoutes.surahNumberParam: '${item.surah.number}',
      },
    );
