import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/widgets/range_label.dart';
import '../../../data/models/surah.dart';
import '../../../domain/entities/hifz_plan.dart';
import '../../hifz_plan/screen/hifz_plan_screen.dart' show openPortion;
import '../../../domain/engine/review_scheduler.dart';
import '../../../domain/entities/review_card.dart';
import '../../mushaf/mushaf_args.dart';
import '../cubit/review_cubit.dart';

/// A card's range in words.
String reviewRangeLabel(BuildContext context, ReviewItem item) => rangeLabel(
  context,
  from: item.card.from,
  to: item.card.to,
  fromSurah: item.fromSurah,
  toSurah: item.toSurah,
);

String tierLabel(ReviewTier tier) => switch (tier) {
  ReviewTier.sabaq => LocaleKeys.reviewTierSabaq.tr(),
  ReviewTier.sabqi => LocaleKeys.reviewTierSabqi.tr(),
  ReviewTier.manzil => LocaleKeys.reviewTierManzil.tr(),
};

/// When a card falls due: today, waiting since an earlier day, tomorrow, or
/// the date — in the app's own numerals.
String dueLabel(BuildContext context, ReviewItem item, DateTime now) {
  final DateTime today = ReviewScheduler.dayOf(now);
  final DateTime due = ReviewScheduler.dayOf(item.card.due);
  if (due == today) return LocaleKeys.reviewDueToday.tr();
  if (due.isBefore(today)) return LocaleKeys.reviewOverdue.tr();
  if (due == ReviewScheduler.addDays(today, 1)) {
    return LocaleKeys.reviewDueTomorrow.tr();
  }
  return LocaleKeys.reviewDueOn.tr(
    args: <String>[
      DateFormat.MMMd(
        context.locale.toString(),
      ).format(due).withLocalisedDigits(),
    ],
  );
}

/// Opens the reading view on a card's range with its review set up and
/// playing.
Future<void> openReview(BuildContext context, ReviewItem item) =>
    context.pushNamed<void>(
      AppRoutes.mushafName,
      extra: MushafArgs(initialAyah: item.card.from, session: item.request),
    );

/// A small tag naming the tier, in the theme's own colours.
class TierChip extends StatelessWidget {
  const TierChip({required this.tier, super.key});

  final ReviewTier tier;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color tone = switch (tier) {
      ReviewTier.sabaq => colors.primary,
      ReviewTier.sabqi => colors.secondary,
      ReviewTier.manzil => colors.tertiary,
    };
    return Container(
      padding: EdgeInsetsDirectional.symmetric(horizontal: 8.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Text(
        tierLabel(tier),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: tone),
      ),
    );
  }
}

/// The home's "today": the ranges due for review, a tap each from playing,
/// and the way to every range kept. Not drawn at all when nothing is due.
class TodayCard extends StatelessWidget {
  const TodayCard({this.plan, super.key});

  /// The reader's hifz plan, whose portion for today comes first.
  final HifzPlan? plan;

  /// More than this and the card would push the index off a phone's screen;
  /// the rest are a tap away.
  static const int shown = 3;

  @override
  Widget build(BuildContext context) {
    final ReviewState state = context.watch<ReviewCubit>().state;
    final List<ReviewItem> due = state.dueToday;
    final Portion? portion = plan?.current;
    final Surah? portionFrom = portion == null
        ? null
        : state.surahs[portion.from.surah];
    final Surah? portionTo = portion == null
        ? null
        : state.surahs[portion.to.surah];
    final bool showPortion = portionFrom != null && portionTo != null;
    if (due.isEmpty && !showPortion) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);
    final DateTime now = context.read<ReviewCubit>().clock();

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(12.w, 10.h, 12.w, 0),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16.r),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(14.w, 8.h, 4.w, 4.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.event_repeat, color: theme.colorScheme.primary),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(
                      due.isEmpty
                          ? LocaleKeys.reviewTodayTitle.tr()
                          : LocaleKeys.reviewToday.tr(
                              args: <String>[due.length.toLocalisedString()],
                            ),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  if (due.isNotEmpty)
                    TextButton(
                      onPressed: () => context.pushNamed(AppRoutes.reviewsName),
                      child: Text(LocaleKeys.reviewAll.tr()),
                    ),
                ],
              ),
              if (showPortion)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsetsDirectional.zero,
                  leading: Icon(Icons.today, color: theme.colorScheme.primary),
                  title: Text(
                    rangeLabel(
                      context,
                      from: portion!.from,
                      to: portion.to,
                      fromSurah: portionFrom,
                      toSurah: portionTo,
                    ),
                  ),
                  subtitle: Text(
                    LocaleKeys.planTodayShort.tr(
                      args: <String>[
                        (plan!.completed + 1).toLocalisedString(),
                        plan!.portions.length.toLocalisedString(),
                      ],
                    ),
                    style: theme.textTheme.labelSmall,
                  ),
                  trailing: IconButton(
                    tooltip: LocaleKeys.planStart.tr(),
                    onPressed: () => openPortion(context, portion),
                    icon: const Icon(Icons.play_circle_outline),
                  ),
                  onTap: () => openPortion(context, portion),
                ),
              for (final ReviewItem item in due.take(shown))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsetsDirectional.zero,
                  title: Text(reviewRangeLabel(context, item)),
                  subtitle: Row(
                    children: <Widget>[
                      TierChip(tier: item.tier),
                      SizedBox(width: 8.w),
                      Flexible(
                        child: Text(
                          dueLabel(context, item, now),
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),
                  trailing: IconButton(
                    tooltip: LocaleKeys.reviewStart.tr(),
                    onPressed: () => openReview(context, item),
                    icon: const Icon(Icons.play_circle_outline),
                  ),
                  onTap: () => openReview(context, item),
                ),
              if (due.length > shown)
                Padding(
                  padding: EdgeInsetsDirectional.only(bottom: 6.h),
                  child: Text(
                    LocaleKeys.reviewMore.tr(
                      args: <String>[(due.length - shown).toLocalisedString()],
                    ),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
