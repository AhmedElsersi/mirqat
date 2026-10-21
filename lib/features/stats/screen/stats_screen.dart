import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/desktop.dart';
import '../../../core/di/injection.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
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
            return ListView(
              padding: EdgeInsetsDirectional.all(16.r),
              children: <Widget>[
                Wrap(
                  spacing: 12.w,
                  runSpacing: 12.h,
                  children: <Widget>[
                    _Tile(
                      icon: Icons.calendar_today_outlined,
                      value: s.daysPractised,
                      label: LocaleKeys.statsDays.tr(),
                    ),
                    _Tile(
                      icon: Icons.headphones_outlined,
                      value: s.minutesListened,
                      label: LocaleKeys.statsMinutes.tr(),
                    ),
                    _Tile(
                      icon: Icons.repeat,
                      value: s.plays,
                      label: LocaleKeys.statsPlays.tr(),
                    ),
                    _Tile(
                      icon: Icons.check_circle_outline,
                      value: s.memorizedAyahs,
                      label: LocaleKeys.statsMemorized.tr(),
                    ),
                  ],
                ),
                SizedBox(height: 16.h),
                Text(
                  LocaleKeys.statsNote.tr(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.value, required this.label});

  final IconData icon;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SizedBox(
      width: 150.w,
      child: Card(
        margin: EdgeInsetsDirectional.zero,
        child: Padding(
          padding: EdgeInsetsDirectional.all(12.r),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, color: theme.colorScheme.primary),
              SizedBox(height: 6.h),
              Text(
                value.toLocalisedString(),
                style: theme.textTheme.titleLarge,
              ),
              Text(label, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
