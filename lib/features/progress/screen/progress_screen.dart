import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/di/injection.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/state/load_status.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/memorization_progress.dart';
import '../../surah_list/widgets/error_view.dart';
import '../cubit/progress_cubit.dart';
import '../cubit/progress_state.dart';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({required this.surahNumber, super.key});

  final int surahNumber;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ProgressCubit>(
      create: (_) => sl<ProgressCubit>()..load(surahNumber),
      child: const _ProgressView(),
    );
  }
}

class _ProgressView extends StatelessWidget {
  const _ProgressView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(LocaleKeys.progressTitle.tr())),
      body: BlocBuilder<ProgressCubit, ProgressScreenState>(
        builder: (BuildContext context, ProgressScreenState state) {
          if (state.status.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.status.isFailure || state.surah == null) {
            return ErrorView(message: state.errorMessage ?? '');
          }

          return Column(
            children: <Widget>[
              Padding(
                padding: EdgeInsetsDirectional.all(16.r),
                child: Text(
                  LocaleKeys.surahListProgress.tr(
                    args: <String>[
                      state.memorizedCount.toLocalisedString(),
                      state.surah!.ayahCount.toLocalisedString(),
                    ],
                  ),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: EdgeInsetsDirectional.symmetric(horizontal: 16.w),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 120.r,
                    mainAxisSpacing: 10.r,
                    crossAxisSpacing: 10.r,
                    mainAxisExtent: 96.h,
                  ),
                  itemCount: state.records.length,
                  itemBuilder: (BuildContext context, int index) =>
                      _AyahTile(record: state.records[index]),
                ),
              ),
              SizedBox(height: 16.h),
            ],
          );
        },
      ),
    );
  }
}

class _AyahTile extends StatelessWidget {
  const _AyahTile({required this.record});

  final MemorizationProgress record;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color statusColor = switch (record.status) {
      MemorizationStatus.notStarted => AppColors.statusNotStarted,
      MemorizationStatus.inProgress => AppColors.statusInProgress,
      MemorizationStatus.memorized => AppColors.statusMemorized,
    };
    final String statusLabel = switch (record.status) {
      MemorizationStatus.notStarted => LocaleKeys.progressStatusNotStarted,
      MemorizationStatus.inProgress => LocaleKeys.progressStatusInProgress,
      MemorizationStatus.memorized => LocaleKeys.progressStatusMemorized,
    };

    return InkWell(
      borderRadius: BorderRadius.circular(12.r),
      onTap: () =>
          context.read<ProgressCubit>().toggleMemorized(record.ayahNumber),
      child: Container(
        padding: EdgeInsetsDirectional.all(8.r),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: statusColor, width: 1.5),
          color: statusColor.withValues(alpha: 0.10),
        ),
        // Scaled down rather than clipped: at the largest system font scale
        // the three lines are taller than the tile.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                LocaleKeys.commonAyahNumber.tr(
                  args: <String>[record.ayahNumber.toLocalisedString()],
                ),
                style: theme.textTheme.titleSmall,
              ),
              SizedBox(height: 4.h),
              Text(
                statusLabel.tr(),
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(color: statusColor),
              ),
              if (record.cumulativeRepeats > 0) ...<Widget>[
                SizedBox(height: 2.h),
                Text(
                  LocaleKeys.progressRepeats.tr(
                    args: <String>[record.cumulativeRepeats.toLocalisedString()],
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
