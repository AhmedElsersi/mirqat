import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
// RELEASE-1.4(review-ladder): needed again by the due list.
// import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../core/extensions/number_extensions.dart';
import '../../core/localization/locale_keys.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/ladder_mark.dart';
import '../../core/widgets/panel.dart';
import '../../core/widgets/range_label.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/surah.dart';
// RELEASE-1.4(bookends)
// import '../../domain/engine/bookends.dart';
import '../../domain/entities/ayah_ref.dart';
import '../../domain/entities/daily_wird.dart';
import '../../domain/entities/hifz_plan.dart';
import '../../domain/entities/review_card.dart';
import '../../domain/entities/session_config.dart';
import '../session/session_request.dart';
import '../home/cubit/home_index_state.dart';
import '../hifz_plan/screen/hifz_plan_screen.dart' show openPortion;
import '../review/cubit/review_cubit.dart';
import '../review/widgets/review_widgets.dart';
import '../wird/widgets/wird_card.dart';
import '../wird/widgets/wird_editor.dart';

/// "Today": the day's work on one page, in the order it is done.
///
/// The new portion first — the one thing to start now, a single tap — then
/// the two reviews the reader set, a suggestion for before sleep or the
/// morning if they asked for one, what the review schedule has due, where
/// they stopped reading, and the plan's progress. Nothing here counts days
/// missed or presses: a reader who comes back after a week sees the same
/// page (docs/BRAND_GUIDE.md §6).
class TodayView extends StatelessWidget {
  const TodayView({
    required this.settings,
    required this.surahs,
    required this.onWirdChanged,
    this.place,
    this.onOpenPlace,
    this.onBookendTaken,
    super.key,
  });

  final AppSettings settings;

  /// Every surah in order: for naming ranges and for the wird editor.
  final List<Surah> surahs;

  /// One part of the wird set to a range, or cleared with null.
  final Future<void> Function(WirdPart part, WirdRange? range) onWirdChanged;

  /// Where the reader stopped, and how to go back there.
  final PlaceItem? place;
  final VoidCallback? onOpenPlace;

  /// Told when a bedtime or morning suggestion is taken up.
  final ValueChanged<String>? onBookendTaken;

  /// More due rows than this and the rest are a tap away.
  static const int shownDue = 3;

  Surah? _surah(int n) => n >= 1 && n <= surahs.length ? surahs[n - 1] : null;

  String? _range(BuildContext context, AyahRef from, AyahRef to) {
    final Surah? first = _surah(from.surah);
    final Surah? last = _surah(to.surah);
    if (first == null || last == null) return null;
    return rangeLabel(
      context,
      from: from,
      to: to,
      fromSurah: first,
      toSurah: last,
    );
  }

  Future<void> _edit(BuildContext context) async {
    if (surahs.isEmpty) return;
    final DailyWird? edited = await showWirdEditor(
      context,
      wird: settings.wird,
      surahs: surahs,
    );
    if (edited == null) return;
    for (final WirdPart part in WirdPart.values) {
      if (edited[part] != settings.wird[part]) {
        await onWirdChanged(part, edited[part]);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // RELEASE-1.4(review-ladder, bookends)
    // final ReviewState review = context.watch<ReviewCubit>().state;
    // final DateTime now = context.read<ReviewCubit>().clock();
    // final Bookend? bookend = settings.bookends
    //     ? const Bookends().suggest(
    //         <ReviewCard>[for (final ReviewItem i in review.items) i.card],
    //         now,
    //         taken: settings.bookendTaken,
    //       )
    //     : null;
    // final ReviewItem? bookendItem = bookend == null
    //     ? null
    //     : review.items
    //           .where((ReviewItem i) => i.card.id == bookend.card.id)
    //           .firstOrNull;
    // // The morning's portion is due on the ladder too: one row, not two.
    // final List<ReviewItem> due = <ReviewItem>[
    //   for (final ReviewItem i in review.dueToday)
    //     if (i.card.id != bookendItem?.card.id) i,
    // ];
    // END RELEASE-1.4(review-ladder, bookends)
    final HifzPlan? plan = settings.hifzPlan;
    final Portion? portion = plan?.current;

    return ListView(
      padding: EdgeInsetsDirectional.fromSTEB(16.w, 8.h, 16.w, 24.h),
      children: <Widget>[
        _Header(onSearch: () => context.pushNamed(AppRoutes.searchName)),
        SizedBox(height: 14.h),
        _NewPortion(
          view: this,
          portion: portion,
          plan: plan,
          onEdit: () => _edit(context),
        ),
        SizedBox(height: 12.h),
        // Side by side and the same height, the button at the foot of each.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final WirdPart part in <WirdPart>[
                WirdPart.recent,
                WirdPart.old,
              ]) ...<Widget>[
                if (part == WirdPart.old) SizedBox(width: 12.w),
                Expanded(
                  child: _ReviewPart(
                    part: part,
                    range: settings.wird[part],
                    surahOf: _surah,
                    onOpen: settings.wird[part] == null
                        ? () => _edit(context)
                        : () =>
                              openWirdPart(context, part, settings.wird[part]!),
                  ),
                ),
              ],
            ],
          ),
        ),
        // RELEASE-1.4(bookends)
        // if (bookend != null && bookendItem != null) ...<Widget>[
        //   SizedBox(height: 12.h),
        //   AppCard(
        //     filled: true,
        //     padding: EdgeInsetsDirectional.zero,
        //     child: BookendRow(
        //       bookend: bookend,
        //       item: bookendItem,
        //       onTaken: onBookendTaken,
        //     ),
        //   ),
        // ],
        // END RELEASE-1.4(bookends)
        // RELEASE-1.4(review-ladder)
        // if (due.isNotEmpty) ...<Widget>[
        //   SectionTitle(
        //     title: LocaleKeys.todayDue.tr(),
        //     action: LocaleKeys.todayAll.tr(
        //       args: <String>[review.dueToday.length.toLocalisedString()],
        //     ),
        //     onAction: () => context.pushNamed(AppRoutes.reviewsName),
        //   ),
        //   AppCard(
        //     padding: EdgeInsetsDirectional.zero,
        //     child: Column(
        //       children: <Widget>[
        //         for (
        //           int i = 0;
        //           i < due.length && i < shownDue;
        //           i++
        //         ) ...<Widget>[
        //           if (i > 0) const Divider(height: 1),
        //           _DueRow(item: due[i], now: now),
        //         ],
        //       ],
        //     ),
        //   ),
        // ],
        // END RELEASE-1.4(review-ladder)
        if (place != null) ...<Widget>[
          SectionTitle(title: LocaleKeys.todayContinue.tr()),
          AppCard(
            padding: EdgeInsetsDirectional.zero,
            child: ListTile(
              onTap: onOpenPlace,
              contentPadding: EdgeInsetsDirectional.fromSTEB(
                16.w,
                6.h,
                12.w,
                6.h,
              ),
              leading: TileIcon(
                settings.readingMark == null
                    ? Icons.bookmark_outline
                    : Icons.bookmark_added,
                color: AppColors.gold,
              ),
              title: Text(
                LocaleKeys.mushafAyahReference.tr(
                  args: <String>[
                    context.locale.languageCode == 'ar'
                        ? place!.surah.nameAr
                        : place!.surah.nameEn,
                    place!.position.ayahNumber.toLocalisedString(),
                  ],
                ),
                style: theme.textTheme.titleSmall,
              ),
              subtitle: Text(
                joinDetails(<String>[
                  LocaleKeys.todayPage.tr(
                    args: <String>[place!.position.page.toLocalisedString()],
                  ),
                  if (settings.readingMark != null) LocaleKeys.todayMark.tr(),
                ]),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
        // RELEASE-1.4(hifz-plan)
        // if (plan != null && portion != null) ...<Widget>[
        //   SizedBox(height: 12.h),
        //   AppCard(
        //     padding: EdgeInsetsDirectional.all(16.r),
        //     onTap: () => context.pushNamed(AppRoutes.hifzPlanName),
        //     child: Column(
        //       crossAxisAlignment: CrossAxisAlignment.stretch,
        //       children: <Widget>[
        //         Row(
        //           children: <Widget>[
        //             Expanded(
        //               child: Text(
        //                 LocaleKeys.todayPlanDays.tr(
        //                   args: <String>[
        //                     _range(context, plan.from, plan.to) ?? '',
        //                     plan.days.toLocalisedString(),
        //                   ],
        //                 ),
        //                 style: theme.textTheme.titleSmall,
        //               ),
        //             ),
        //             Text(
        //               LocaleKeys.todayPlanProgress.tr(
        //                 args: <String>[
        //                   plan.completed.toLocalisedString(),
        //                   plan.portions.length.toLocalisedString(),
        //                 ],
        //               ),
        //               style: theme.textTheme.labelMedium?.copyWith(
        //                 color: theme.colorScheme.onSurfaceVariant,
        //               ),
        //             ),
        //           ],
        //         ),
        //         SizedBox(height: 10.h),
        //         ProgressBar(
        //           value: plan.portions.isEmpty
        //               ? 0
        //               : plan.completed / plan.portions.length,
        //         ),
        //       ],
        //     ),
        //   ),
        // ],
        // END RELEASE-1.4(hifz-plan)
      ],
    );
  }
}

/// The date, and the page's name.
class _Header extends StatelessWidget {
  const _Header({required this.onSearch});

  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                DateFormat.MMMMEEEEd(
                  context.locale.toString(),
                ).format(DateTime.now()).withLocalisedDigits(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                LocaleKeys.todayTitle.tr(),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        IconButton.outlined(
          style: IconButton.styleFrom(
            backgroundColor: theme.colorScheme.surface,
          ),
          onPressed: onSearch,
          tooltip: LocaleKeys.searchTitle.tr(),
          icon: const Icon(Icons.search),
        ),
      ],
    );
  }
}

/// Today's new portion, the page's one prominent card: the reader's own if
/// they set one, else the plan's, else the way to set either.
class _NewPortion extends StatelessWidget {
  const _NewPortion({
    required this.view,
    required this.portion,
    required this.plan,
    required this.onEdit,
  });

  final TodayView view;
  final Portion? portion;
  final HifzPlan? plan;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final WirdRange? fresh = view.settings.wird[WirdPart.fresh];
    final AppSettings s = view.settings;

    String? title;
    String subtitle;
    VoidCallback? start;
    if (fresh != null) {
      title = view._range(context, fresh.from, fresh.to);
      subtitle = joinDetails(<String>[
        switch (s.defaultConnectMode) {
          ConnectMode.cumulative => LocaleKeys.sessionSetupConnectCumulative,
          ConnectMode.continuous => LocaleKeys.sessionSetupConnectContinuous,
          ConnectMode.none => LocaleKeys.sessionSetupConnectNone,
        }.tr(),
        LocaleKeys.progressRepeats.tr(
          args: <String>[s.defaultRepeatCount.toLocalisedString()],
        ),
        if (s.defaultRecallRounds > 0) LocaleKeys.todayRecallRound.tr(),
      ]);
      start = () => openWirdPart(context, WirdPart.fresh, fresh);
    } else if (portion != null && plan != null) {
      title = view._range(context, portion!.from, portion!.to);
      subtitle = LocaleKeys.planTodayShort.tr(
        args: <String>[
          (plan!.completed + 1).toLocalisedString(),
          plan!.portions.length.toLocalisedString(),
        ],
      );
      start = () => openPortion(context, portion!);
    } else {
      // RELEASE-1.4(hifz-plan): the body that offers a plan.
      // subtitle = LocaleKeys.todayEmptyBody.tr();
      subtitle = LocaleKeys.todayEmptyBodyNoPlan.tr(); // RELEASE-1.4: remove
    }

    const Color onHero = AppColors.cream;
    return Material(
      color: AppColors.forest,
      borderRadius: BorderRadius.circular(26.r),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsetsDirectional.all(20.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                AppTag(
                  label: start == null
                      ? LocaleKeys.todayTitle.tr()
                      : wirdPartLabel(WirdPart.fresh),
                  onHero: true,
                ),
                const Spacer(),
                LadderMark(
                  current: start == null ? 0 : 2,
                  color: onHero.withValues(alpha: 0.18),
                  doneColor: AppColors.rungDoneOnHero,
                ),
              ],
            ),
            SizedBox(height: 14.h),
            Text(
              title ?? LocaleKeys.todayEmptyTitle.tr(),
              style: theme.textTheme.titleLarge?.copyWith(
                color: onHero,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: onHero.withValues(alpha: 0.78),
              ),
            ),
            SizedBox(height: 18.h),
            // The button at the start, the second action at the far end; where
            // the two do not fit side by side, the second goes under the first
            // rather than squeeze the button.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8.w,
              runSpacing: 4.h,
              children: <Widget>[
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: onHero,
                    foregroundColor: AppColors.forest,
                    minimumSize: Size(0, 48.r),
                  ),
                  onPressed: start ?? onEdit,
                  icon: Icon(
                    start == null ? Icons.edit_outlined : Icons.play_arrow,
                  ),
                  label: Text(
                    start == null
                        ? LocaleKeys.todaySet.tr()
                        : LocaleKeys.todayStart.tr(),
                  ),
                ),
                // RELEASE-1.4(hifz-plan)
                // if (start == null)
                //   TextButton(
                //     style: TextButton.styleFrom(foregroundColor: onHero),
                //     onPressed: () => context.pushNamed(AppRoutes.hifzPlanName),
                //     child: Text(LocaleKeys.todayPlan.tr()),
                //   )
                // else
                // END RELEASE-1.4(hifz-plan)
                if (start != null) // RELEASE-1.4(hifz-plan): remove this line
                  IconButton(
                    color: onHero,
                    tooltip: LocaleKeys.wirdEdit.tr(),
                    onPressed: onEdit,
                    icon: const Icon(Icons.tune),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the two reviews the reader set, or the way to add it: the tag,
/// the surah, the ayahs, and at the foot how it is worked and the button.
class _ReviewPart extends StatelessWidget {
  const _ReviewPart({
    required this.part,
    required this.range,
    required this.surahOf,
    required this.onOpen,
  });

  final WirdPart part;
  final WirdRange? range;
  final Surah? Function(int) surahOf;
  final VoidCallback onOpen;

  /// How this part is worked, in two or three words: the preset's repeats
  /// and recall, or its joining and link test.
  String _mode() {
    final SessionPreset preset = wirdPartPreset(part);
    return joinDetails(<String>[
      if (preset.repeatCount case final int n)
        LocaleKeys.progressRepeats.tr(args: <String>[n.toLocalisedString()]),
      if (preset.connectMode == ConnectMode.continuous)
        LocaleKeys.sessionSetupConnectContinuous.tr(),
      if ((preset.recallRounds ?? 0) > 0) LocaleKeys.todayRecall.tr(),
      if (preset.chainRecall ?? false) LocaleKeys.todayChain.tr(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final WirdRange? range = this.range;
    final Surah? first = range == null ? null : surahOf(range.from.surah);
    final Surah? last = range == null ? null : surahOf(range.to.surah);
    final bool set = range != null && first != null && last != null;
    final bool arabic = context.locale.languageCode == 'ar';
    String name(Surah s) => arabic ? s.nameAr : s.nameEn;

    final String title;
    final String? ayahs;
    if (!set) {
      title = LocaleKeys.todayAdd.tr();
      ayahs = null;
    } else if (first.number != last.number) {
      title = '${name(first)} – ${name(last)}';
      ayahs = range.from.ayah == 1 && range.to.ayah == last.ayahCount
          ? LocaleKeys.todayWholeSurahs.tr()
          : LocaleKeys.todayAyahsCross.tr(
              args: <String>[
                range.from.ayah.toLocalisedString(),
                range.to.ayah.toLocalisedString(),
              ],
            );
    } else {
      title = LocaleKeys.mushafSurahLabel.tr(args: <String>[name(first)]);
      ayahs = range.from.ayah == 1 && range.to.ayah == first.ayahCount
          ? LocaleKeys.todayWholeSurah.tr()
          : LocaleKeys.todayAyahsSpan.tr(
              args: <String>[
                range.from.ayah.toLocalisedString(),
                range.to.ayah.toLocalisedString(),
              ],
            );
    }
    final TextStyle? muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return AppCard(
      onTap: onOpen,
      padding: EdgeInsetsDirectional.all(16.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppTag(label: wirdPartLabel(part)),
          ),
          SizedBox(height: 10.h),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: set ? null : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (ayahs != null) Text(ayahs, style: muted),
          const Spacer(),
          SizedBox(height: 12.h),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  set ? _mode() : '',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              PlayButton(
                soft: true,
                onPressed: onOpen,
                tooltip: set
                    ? LocaleKeys.reviewStart.tr()
                    : LocaleKeys.wirdAdd.tr(),
                icon: set ? Icons.play_arrow : Icons.add,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A review the schedule has due: its place on the ladder, its range, when.
// RELEASE-1.4(review-ladder): remove the ignore once the due list is back.
// ignore: unused_element
class _DueRow extends StatelessWidget {
  const _DueRow({required this.item, required this.now});

  final ReviewItem item;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListTile(
      onTap: () => openReview(context, item),
      // The rung the passage stands on: new on the first, recent on the
      // second, old at the top.
      leading: LadderMark(
        current: switch (item.tier) {
          ReviewTier.sabaq => 0,
          ReviewTier.sabqi => 1,
          ReviewTier.manzil => 3,
        },
      ),
      title: Text(
        reviewRangeLabel(context, item),
        style: theme.textTheme.titleSmall,
      ),
      // Its rung and the last word on it; that it is due is what the
      // section says.
      subtitle: Text(
        joinDetails(<String>[
          tierLabel(item.tier),
          if (item.card.lastGrade case final Grade g)
            LocaleKeys.reviewLastGrade.tr(
              args: <String>[
                switch (g) {
                  Grade.solid => LocaleKeys.reviewGradeSolid,
                  Grade.shaky => LocaleKeys.reviewGradeShaky,
                  Grade.forgot => LocaleKeys.reviewGradeForgot,
                }.tr(),
              ],
            )
          else
            dueLabel(context, item, now),
        ]),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: PlayButton(
        soft: true,
        tooltip: LocaleKeys.reviewStart.tr(),
        onPressed: () => openReview(context, item),
      ),
    );
  }
}
