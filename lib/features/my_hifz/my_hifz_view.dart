import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../core/extensions/number_extensions.dart';
import '../../core/localization/locale_keys.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/ladder_mark.dart';
import '../../domain/entities/hifz_plan.dart';
import '../../domain/entities/practice_stats.dart';
import '../../domain/entities/review_card.dart';
import '../review/cubit/review_cubit.dart';
import '../review/widgets/review_widgets.dart' show tierLabel;
import '../settings/cubit/settings_cubit.dart';
import '../stats/cubit/stats_cubit.dart';
import 'cubit/my_hifz_cubit.dart';

/// "My hifz": what has been memorized, across the mushaf, and every tool for
/// keeping it — the review schedule, the plan, weak spots, the mutashabihat,
/// the practice record, the backup. These were rows in Settings; they are
/// things to do, not things to set.
class MyHifzView extends StatelessWidget {
  const MyHifzView({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MyHifzState hifz = context.watch<MyHifzCubit>().state;
    final ReviewState review = context.watch<ReviewCubit>().state;
    final PracticeStats? stats = context.watch<StatsCubit>().state.stats;
    final HifzPlan? plan = context.select<SettingsCubit, HifzPlan?>(
      (SettingsCubit c) => c.state.settings.hifzPlan,
    );

    int inTier(ReviewTier tier) =>
        review.items.where((ReviewItem i) => i.tier == tier).length;

    return ListView(
      padding: EdgeInsetsDirectional.fromSTEB(16.w, 8.h, 16.w, 24.h),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                LocaleKeys.myHifzTitle.tr(),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton.outlined(
              tooltip: LocaleKeys.backupTitle.tr(),
              onPressed: () => context.pushNamed(AppRoutes.backupName),
              icon: const Icon(Icons.save_alt),
            ),
          ],
        ),
        SizedBox(height: 14.h),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          LocaleKeys.myHifzMemorized.tr(),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          hifz.memorized.toLocalisedString(),
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  LadderMark(current: hifz.memorized == 0 ? 0 : 2),
                ],
              ),
              SizedBox(height: 14.h),
              _JuzMap(shares: hifz.juzShares),
              SizedBox(height: 6.h),
              Row(
                children: <Widget>[
                  Text(
                    LocaleKeys.myHifzFirstJuz.tr(),
                    style: theme.textTheme.labelSmall,
                  ),
                  const Spacer(),
                  Text(
                    LocaleKeys.myHifzLastJuz.tr(),
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ],
          ),
        ),
        _Title(
          title: LocaleKeys.myHifzReview.tr(),
          action: LocaleKeys.myHifzSchedule.tr(),
          onAction: () => context.pushNamed(AppRoutes.reviewsName),
        ),
        Row(
          children: <Widget>[
            for (final ReviewTier tier in ReviewTier.values) ...<Widget>[
              if (tier != ReviewTier.values.first) SizedBox(width: 10.w),
              Expanded(
                child: _Card(
                  onTap: () => context.pushNamed(AppRoutes.reviewsName),
                  child: Column(
                    children: <Widget>[
                      Text(
                        inTier(tier).toLocalisedString(),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        tierLabel(tier),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
        SizedBox(height: 12.h),
        _Card(
          onTap: () => context.pushNamed(AppRoutes.hifzPlanName),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const _Icon(Icons.flag_circle_outlined),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          LocaleKeys.planTitle.tr(),
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          plan == null
                              ? LocaleKeys.myHifzPlanNone.tr()
                              : plan.isFinished
                              ? LocaleKeys.planFinished.tr()
                              : LocaleKeys.planProgress.tr(
                                  args: <String>[
                                    plan.completed.toLocalisedString(),
                                    plan.portions.length.toLocalisedString(),
                                  ],
                                ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (plan != null && plan.portions.isNotEmpty) ...<Widget>[
                SizedBox(height: 12.h),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3.r),
                  child: LinearProgressIndicator(
                    value: plan.completed / plan.portions.length,
                    minHeight: 6.r,
                    color: AppColors.gold,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ],
          ),
        ),
        _Title(title: LocaleKeys.myHifzTools.tr()),
        _Card(
          padding: EdgeInsetsDirectional.zero,
          child: Column(
            children: <Widget>[
              _Row(
                icon: Icons.flag_outlined,
                iconColor: theme.colorScheme.error,
                title: LocaleKeys.weakSpotsTitle.tr(),
                subtitle: LocaleKeys.myHifzWeakHint.tr(),
                count: hifz.weakSpots,
                onTap: () => context.pushNamed(AppRoutes.weakSpotsName),
              ),
              const Divider(height: 1),
              _Row(
                icon: Icons.compare_arrows,
                title: LocaleKeys.mutashabihatTitle.tr(),
                subtitle: LocaleKeys.myHifzPhrases.tr(
                  args: <String>[hifz.phrases.toLocalisedString()],
                ),
                onTap: () => context.pushNamed(AppRoutes.mutashabihatName),
              ),
              const Divider(height: 1),
              _Row(
                icon: Icons.insights_outlined,
                title: LocaleKeys.statsTitle.tr(),
                subtitle: stats == null
                    ? LocaleKeys.statsHint.tr()
                    : LocaleKeys.myHifzPractice.tr(
                        args: <String>[
                          stats.daysPractised.toLocalisedString(),
                          stats.minutesListened.toLocalisedString(),
                        ],
                      ),
                onTap: () => context.pushNamed(AppRoutes.statsName),
              ),
              const Divider(height: 1),
              _Row(
                icon: Icons.save_alt,
                title: LocaleKeys.backupTitle.tr(),
                subtitle: LocaleKeys.backupHint.tr(),
                onTap: () => context.pushNamed(AppRoutes.backupName),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Thirty cells, one per juz in reading order, tinted by how much of each
/// is memorized. A map of the mushaf, not a score.
class _JuzMap extends StatelessWidget {
  const _JuzMap({required this.shares});

  final List<double> shares;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color empty = theme.colorScheme.surfaceContainerHighest;
    final Color full = theme.brightness == Brightness.dark
        ? AppColors.sabrDark
        : AppColors.sabrLight;
    final List<double> cells = shares.isEmpty
        ? List<double>.filled(30, 0)
        : shares;
    return Semantics(
      label: LocaleKeys.myHifzJuzMap.tr(),
      // Ten to a row, three rows, whatever the width: the cells share it.
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final double gap = 4.r;
          final double cell = (box.maxWidth - gap * 9) / 10;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: <Widget>[
              for (final double share in cells)
                Container(
                  width: cell,
                  height: 22.r,
                  decoration: BoxDecoration(
                    color: share <= 0
                        ? empty
                        : Color.lerp(empty, full, 0.3 + 0.7 * share),
                    borderRadius: BorderRadius.circular(5.r),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.title, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(4.w, 24.h, 4.w, 8.h),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.onTap, this.padding});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18.r),
        side: BorderSide(color: colors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: padding ?? EdgeInsetsDirectional.all(16.r),
          child: child,
        ),
      ),
    );
  }
}

class _Icon extends StatelessWidget {
  const _Icon(this.icon, {this.color});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    width: 40.r,
    height: 40.r,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12.r),
    ),
    child: Icon(icon, color: color),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
    this.count,
  });

  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      leading: _Icon(icon, color: iconColor),
      title: Text(title, style: theme.textTheme.titleSmall),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (count != null && count! > 0)
            Container(
              padding: EdgeInsetsDirectional.symmetric(
                horizontal: 9.w,
                vertical: 2.h,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                count!.toLocalisedString(),
                style: theme.textTheme.labelMedium,
              ),
            ),
          const Icon(Icons.chevron_left),
        ],
      ),
    );
  }
}
