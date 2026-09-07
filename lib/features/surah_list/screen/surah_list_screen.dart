import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/injection.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/state/load_status.dart';
import '../cubit/surah_list_cubit.dart';
import '../cubit/surah_list_state.dart';
import '../widgets/error_view.dart';
import '../widgets/surah_row.dart';

/// Home. Lists exactly what the catalog holds — one row in Milestone 1, which
/// is correct rather than a gap to fill with placeholders.
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

class _SurahListView extends StatelessWidget {
  const _SurahListView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(LocaleKeys.appName.tr()),
        actions: <Widget>[
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

          return ListView.separated(
            padding: EdgeInsetsDirectional.only(bottom: 24.h),
            itemCount: state.items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (BuildContext context, int index) {
              final SurahListItem item = state.items[index];
              return SurahRow(
                item: item,
                onTap: () => context.pushNamed(
                  AppRoutes.sessionSetupName,
                  pathParameters: <String, String>{
                    AppRoutes.surahNumberParam: '${item.surah.number}',
                  },
                ),
                onProgressTap: () => context.pushNamed(
                  AppRoutes.progressName,
                  pathParameters: <String, String>{
                    AppRoutes.surahNumberParam: '${item.surah.number}',
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
