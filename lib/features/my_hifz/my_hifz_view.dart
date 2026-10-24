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
import '../../core/widgets/panel.dart';
import '../../core/widgets/range_label.dart';
import '../../data/models/surah.dart';
import '../../domain/entities/hifz_plan.dart';
import '../../domain/entities/practice_stats.dart';
import '../../domain/entities/review_card.dart';
import '../home/cubit/home_index_cubit.dart';
import '../review/cubit/review_cubit.dart';
import '../review/widgets/review_widgets.dart' show tierLabel;
import '../settings/cubit/settings_cubit.dart';
import '../stats/cubit/stats_cubit.dart';
import '../surah_list/screen/surah_list_screen.dart' show openMushaf;
import 'cubit/my_hifz_cubit.dart';

/// "My hifz": what has been memorized, across the mushaf, and every tool for
/// keeping it — the review schedule, the plan, weak spots, the mutashabihat,
/// reciting to a listener, the practice record, the backup. These were rows
/// in Settings; they are things to do, not things to set.
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
    final EdgeInsetsDirectional cardPadding = EdgeInsetsDirectional.all(16.r);

    int inTier(ReviewTier tier) =>
        review.items.where((ReviewItem i) => i.tier == tier).length;

    return ListView(
      padding: EdgeInsetsDirectional.fromSTEB(16.w, 6.h, 16.w, 24.h),
      children: <Widget>[
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(4.w, 0, 4.w, 14.h),
          child: Row(
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
                style: IconButton.styleFrom(
                  backgroundColor: theme.colorScheme.surface,
                ),
                tooltip: LocaleKeys.backupTitle.tr(),
                onPressed: () => context.pushNamed(AppRoutes.backupName),
                icon: const Icon(Icons.save_alt),
              ),
            ],
          ),
        ),
        // What has been memorized, across the mushaf: a map, not a score.
        AppCard(
          padding: cardPadding,
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
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    LocaleKeys.myHifzLastJuz.tr(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SectionTitle(
          title: LocaleKeys.myHifzReview.tr(),
          action: LocaleKeys.myHifzSchedule.tr(),
          onAction: () => context.pushNamed(AppRoutes.reviewsName),
        ),
        // The three rungs, each with how many passages stand on it — the
        // same height, whatever their labels wrap to.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final ReviewTier tier in ReviewTier.values) ...<Widget>[
                if (tier != ReviewTier.values.first) SizedBox(width: 10.w),
                Expanded(
                  child: AppCard(
                    padding: cardPadding,
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
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall?.copyWith(
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
        ),
        SizedBox(height: 12.h),
        _PlanCard(plan: plan, padding: cardPadding),
        SectionTitle(title: LocaleKeys.myHifzTools.tr()),
        AppCard(
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
              // Reciting to a listener happens over the page, so the row
              // opens the mushaf where the reader last was, in that mode.
              _Row(
                icon: Icons.hearing_outlined,
                title: LocaleKeys.tasmeeStart.tr(),
                subtitle: LocaleKeys.tasmeeHint.tr(),
                onTap: () => openMushaf(
                  context,
                  page: context
                      .read<HomeIndexCubit>()
                      .state
                      .last
                      ?.position
                      .page,
                  tasmee: true,
                ),
              ),
              const Divider(height: 1),
              _Row(
                icon: Icons.calendar_month_outlined,
                title: LocaleKeys.statsTitle.tr(),
                subtitle: joinDetails(<String>[
                  if (stats != null)
                    LocaleKeys.myHifzPractice.tr(
                      args: <String>[
                        stats.daysPractised.toLocalisedString(),
                        stats.minutesListened.toLocalisedString(),
                      ],
                    ),
                  LocaleKeys.myHifzOnDevice.tr(),
                ]),
                onTap: () => context.pushNamed(AppRoutes.statsName),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The plan: how long it is and where it stands, in one row with a bar —
/// or, without one, the offer to make one.
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.padding});

  final HifzPlan? plan;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final HifzPlan? plan = this.plan;
    final TextStyle? small = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    String subtitle() {
      if (plan == null) return LocaleKeys.myHifzPlanNone.tr();
      if (plan.isFinished) return LocaleKeys.planFinished.tr();
      final Portion? portion = plan.current;
      final HomeIndexCubit index = context.read<HomeIndexCubit>();
      final Surah? a = portion == null
          ? null
          : index.surahOf(portion.from.surah);
      final Surah? b = portion == null ? null : index.surahOf(portion.to.surah);
      final Surah? first = index.surahOf(plan.from.surah);
      final Surah? last = index.surahOf(plan.to.surah);
      final String days = plan.days.toLocalisedString();
      return joinDetails(<String>[
        if (first != null && last != null)
          LocaleKeys.myHifzPlanSpan.tr(
            args: <String>[
              rangeLabel(
                context,
                from: plan.from,
                to: plan.to,
                fromSurah: first,
                toSurah: last,
              ),
              days,
            ],
          )
        else
          LocaleKeys.planDaysCount.tr(args: <String>[days]),
        if (portion != null && a != null && b != null)
          LocaleKeys.myHifzPortion.tr(
            args: <String>[
              (plan.completed + 1).toLocalisedString(),
              rangeLabel(
                context,
                from: portion.from,
                to: portion.to,
                fromSurah: a,
                toSurah: b,
              ),
            ],
          ),
      ]);
    }

    return AppCard(
      padding: padding,
      onTap: () => context.pushNamed(AppRoutes.hifzPlanName),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const TileIcon(Icons.flag_circle_outlined),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      LocaleKeys.planTitle.tr(),
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(subtitle(), style: small),
                  ],
                ),
              ),
              if (plan != null && plan.portions.isNotEmpty) ...<Widget>[
                SizedBox(width: 12.w),
                Text(
                  LocaleKeys.todayPlanProgress.tr(
                    args: <String>[
                      plan.completed.toLocalisedString(),
                      plan.portions.length.toLocalisedString(),
                    ],
                  ),
                  style: small,
                ),
              ],
            ],
          ),
          if (plan != null && plan.portions.isNotEmpty) ...<Widget>[
            SizedBox(height: 12.h),
            ProgressBar(value: plan.completed / plan.portions.length),
          ],
        ],
      ),
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
                    // Three tints, as the map has them: begun, about half,
                    // whole.
                    color: share <= 0
                        ? empty
                        : share >= 1
                        ? full
                        : Color.lerp(empty, full, share >= 0.5 ? 0.7 : 0.35),
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
      contentPadding: EdgeInsetsDirectional.fromSTEB(14.w, 4.h, 10.w, 4.h),
      leading: TileIcon(icon, color: iconColor),
      title: Text(title, style: theme.textTheme.titleSmall),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (count != null && count! > 0) ...<Widget>[
            AppTag(label: count!.toLocalisedString()),
            SizedBox(width: 4.w),
          ],
          Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
        ],
      ),
    );
  }
}
