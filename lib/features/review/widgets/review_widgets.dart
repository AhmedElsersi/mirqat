import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/widgets/panel.dart';
import '../../../core/widgets/range_label.dart';
import '../../../domain/engine/bookends.dart';
import '../../../domain/engine/review_scheduler.dart';
import '../../../domain/entities/review_card.dart';
import '../../mushaf/mushaf_args.dart';
import '../../session/session_request.dart';
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

/// When a card falls due: now, tomorrow, or the date — in the app's own
/// numerals.
String dueLabel(BuildContext context, ReviewItem item, DateTime now) {
  final DateTime today = ReviewScheduler.dayOf(now);
  final DateTime due = ReviewScheduler.dayOf(item.card.due);
  // Waiting since an earlier day is simply due: when it was missed is not
  // the reader's to be reminded of (docs/BRAND_GUIDE.md §6).
  if (!due.isAfter(today)) return LocaleKeys.reviewDueToday.tr();
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

/// Today's new portion before sleep, heard straight through once; or the
/// next morning, recited back lightly. A suggestion, said as one — and gone
/// once it is taken up.
class BookendRow extends StatelessWidget {
  const BookendRow({
    required this.bookend,
    required this.item,
    this.onTaken,
    super.key,
  });

  final Bookend bookend;
  final ReviewItem item;
  final ValueChanged<String>? onTaken;

  void _open(BuildContext context) {
    onTaken?.call(bookend.key);
    context.pushNamed<void>(
      AppRoutes.mushafName,
      extra: MushafArgs(
        initialAyah: item.card.from,
        session: SessionRequest(
          from: item.card.from,
          to: item.card.to,
          preset: bookend.time == BookendTime.night
              ? SessionPreset.listen
              : SessionPreset.recent,
          autostart: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool night = bookend.time == BookendTime.night;
    return ListTile(
      onTap: () => _open(context),
      contentPadding: EdgeInsetsDirectional.fromSTEB(16.w, 6.h, 12.w, 6.h),
      leading: TileIcon(
        night ? Icons.bedtime_outlined : Icons.wb_twilight,
        background: theme.colorScheme.surface,
      ),
      title: Text(
        night
            ? LocaleKeys.reviewBookendNightTitle.tr()
            : LocaleKeys.reviewBookendMorningTitle.tr(),
        style: theme.textTheme.titleSmall,
      ),
      subtitle: Text(
        night
            ? LocaleKeys.reviewBookendNightBody.tr()
            : LocaleKeys.reviewBookendMorningBody.tr(),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
