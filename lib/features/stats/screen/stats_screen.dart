import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/desktop.dart';
import '../../../core/di/injection.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/widgets/ladder_mark.dart';
import '../../../core/widgets/panel.dart';
import '../../../domain/entities/practice_stats.dart';
import '../cubit/stats_cubit.dart';

/// What the reader has done, added up and said plainly: no score, no badge,
/// no run of days to keep alive, nothing about what was not done
/// (docs/BRAND_GUIDE.md §6).
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider<StatsCubit>(
    create: (_) => sl<StatsCubit>()..load(),
    child: Scaffold(
      appBar: AppBar(title: Text(LocaleKeys.statsTitle.tr())),
      body: DesktopWidth(
        child: BlocBuilder<StatsCubit, StatsState>(
          builder: (BuildContext context, StatsState state) {
            final PracticeStats? s = state.stats;
            if (s == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final ThemeData theme = Theme.of(context);
            return ListView(
              padding: EdgeInsetsDirectional.fromSTEB(16.w, 12.h, 16.w, 32.h),
              children: <Widget>[
                AppCard(
                  padding: EdgeInsetsDirectional.all(16.r),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              LocaleKeys.statsDays.tr(),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              s.daysPractised.toLocalisedString(),
                              style: theme.textTheme.displaySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              LocaleKeys.statsDaysHint.tr(),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      LadderMark(current: s.daysPractised == 0 ? 0 : 3),
                    ],
                  ),
                ),
                SizedBox(height: 12.h),
                // Each pair the same height, whatever its labels wrap to.
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(
                        child: _Stat(
                          value: s.minutesListened,
                          label: LocaleKeys.statsMinutes.tr(),
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: _Stat(
                          value: s.plays,
                          label: LocaleKeys.statsPlays.tr(),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12.h),
                // Each pair the same height, whatever its labels wrap to.
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(
                        child: _Stat(
                          value: s.memorizedAyahs,
                          label: LocaleKeys.statsMemorized.tr(),
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: _Stat(
                          value: s.reviewCards,
                          label: LocaleKeys.statsReviewCards.tr(),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 18.h),
                AppNote(
                  LocaleKeys.statsNote.tr(),
                  icon: Icons.smartphone_outlined,
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

/// One number, and what it counts.
class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AppCard(
      padding: EdgeInsetsDirectional.all(16.r),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            value.toLocalisedString(),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 2.h),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
