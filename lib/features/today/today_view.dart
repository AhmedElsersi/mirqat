import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../core/extensions/number_extensions.dart';
import '../../core/localization/locale_keys.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/ladder_mark.dart';
import '../../core/widgets/range_label.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/surah.dart';
import '../../domain/engine/bookends.dart';
import '../../domain/entities/ayah_ref.dart';
import '../../domain/entities/daily_wird.dart';
import '../../domain/entities/hifz_plan.dart';
import '../../domain/entities/review_card.dart';
import '../../domain/entities/session_config.dart';
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
    final ReviewState review = context.watch<ReviewCubit>().state;
    final DateTime now = context.read<ReviewCubit>().clock();
    final Bookend? bookend = settings.bookends
        ? const Bookends().suggest(
            <ReviewCard>[for (final ReviewItem i in review.items) i.card],
            now,
            taken: settings.bookendTaken,
          )
        : null;
    final ReviewItem? bookendItem = bookend == null
        ? null
        : review.items
              .where((ReviewItem i) => i.card.id == bookend.card.id)
              .firstOrNull;
    // The morning's portion is due on the ladder too: one row, not two.
    final List<ReviewItem> due = <ReviewItem>[
      for (final ReviewItem i in review.dueToday)
        if (i.card.id != bookendItem?.card.id) i,
    ];
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final WirdPart part in <WirdPart>[
              WirdPart.recent,
              WirdPart.old,
            ]) ...<Widget>[
              if (part == WirdPart.old) SizedBox(width: 12.w),
              Expanded(
                child: _ReviewPart(
                  part: part,
                  label: settings.wird[part] == null
                      ? null
                      : _range(
                          context,
                          settings.wird[part]!.from,
                          settings.wird[part]!.to,
                        ),
                  onOpen: settings.wird[part] == null
                      ? () => _edit(context)
                      : () => openWirdPart(context, part, settings.wird[part]!),
                ),
              ),
            ],
          ],
        ),
        if (bookend != null && bookendItem != null) ...<Widget>[
          SizedBox(height: 12.h),
          _Tile(
            filled: true,
            child: BookendRow(
              bookend: bookend,
              item: bookendItem,
              onTaken: onBookendTaken,
            ),
          ),
        ],
        if (due.isNotEmpty) ...<Widget>[
          _SectionTitle(
            title: LocaleKeys.todayDue.tr(),
            action: LocaleKeys.todayAll.tr(
              args: <String>[review.dueToday.length.toLocalisedString()],
            ),
            onAction: () => context.pushNamed(AppRoutes.reviewsName),
          ),
          _Tile(
            child: Column(
              children: <Widget>[
                for (
                  int i = 0;
                  i < due.length && i < shownDue;
                  i++
                ) ...<Widget>[
                  if (i > 0) const Divider(height: 1),
                  _DueRow(item: due[i], now: now),
                ],
              ],
            ),
          ),
        ],
        if (place != null) ...<Widget>[
          _SectionTitle(title: LocaleKeys.todayContinue.tr()),
          _Tile(
            child: ListTile(
              onTap: onOpenPlace,
              leading: Icon(
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
              ),
              trailing: const Icon(Icons.chevron_left),
            ),
          ),
        ],
        if (plan != null && portion != null) ...<Widget>[
          SizedBox(height: 12.h),
          _Tile(
            padding: EdgeInsetsDirectional.all(16.r),
            onTap: () => context.pushNamed(AppRoutes.hifzPlanName),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        LocaleKeys.todayPlan.tr(),
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    Text(
                      LocaleKeys.todayPlanProgress.tr(
                        args: <String>[
                          plan.completed.toLocalisedString(),
                          plan.portions.length.toLocalisedString(),
                        ],
                      ),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10.h),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3.r),
                  child: LinearProgressIndicator(
                    value: plan.portions.isEmpty
                        ? 0
                        : plan.completed / plan.portions.length,
                    minHeight: 6.r,
                    color: AppColors.gold,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
          ),
        ],
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
      subtitle = LocaleKeys.todayEmptyBody.tr();
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
                _Tag(
                  label: start == null
                      ? LocaleKeys.todayTitle.tr()
                      : wirdPartLabel(WirdPart.fresh),
                  onHero: true,
                ),
                const Spacer(),
                LadderMark(
                  current: start == null ? 0 : 2,
                  color: onHero.withValues(alpha: 0.18),
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
            // A wrap, not a row: on a narrow phone with a large font the
            // second action goes under the first instead of off the card.
            Wrap(
              spacing: 8.w,
              runSpacing: 4.h,
              crossAxisAlignment: WrapCrossAlignment.center,
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
                if (start == null)
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: onHero),
                    onPressed: () => context.pushNamed(AppRoutes.hifzPlanName),
                    child: Text(LocaleKeys.todayPlan.tr()),
                  )
                else
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

/// One of the two reviews the reader set, or the way to add it.
class _ReviewPart extends StatelessWidget {
  const _ReviewPart({
    required this.part,
    required this.label,
    required this.onOpen,
  });

  final WirdPart part;
  final String? label;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool set = label != null;
    return _Tile(
      onTap: onOpen,
      padding: EdgeInsetsDirectional.all(14.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Tag(label: wirdPartLabel(part)),
          SizedBox(height: 10.h),
          Text(
            label ?? LocaleKeys.todayAdd.tr(),
            style: theme.textTheme.titleSmall?.copyWith(
              color: set ? null : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: 10.h),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: IconButton.filledTonal(
              onPressed: onOpen,
              tooltip: set
                  ? LocaleKeys.reviewStart.tr()
                  : LocaleKeys.wirdAdd.tr(),
              icon: Icon(set ? Icons.play_arrow : Icons.add),
            ),
          ),
        ],
      ),
    );
  }
}

/// A review the schedule has due: its place on the ladder, its range, when.
class _DueRow extends StatelessWidget {
  const _DueRow({required this.item, required this.now});

  final ReviewItem item;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () => openReview(context, item),
      leading: LadderMark(
        current: switch (item.tier) {
          ReviewTier.sabaq => 1,
          ReviewTier.sabqi => 2,
          ReviewTier.manzil => 3,
        },
      ),
      title: Text(reviewRangeLabel(context, item)),
      subtitle: Text(
        joinDetails(<String>[
          tierLabel(item.tier),
          dueLabel(context, item, now),
        ]),
      ),
      trailing: IconButton.filledTonal(
        tooltip: LocaleKeys.reviewStart.tr(),
        onPressed: () => openReview(context, item),
        icon: const Icon(Icons.play_arrow),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.action, this.onAction});

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

/// A rounded card on the page's surface.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.child,
    this.onTap,
    this.padding,
    this.filled = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  /// Tinted rather than outlined: a suggestion, not a task.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Material(
      color: filled ? colors.surfaceContainerHighest : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18.r),
        side: filled ? BorderSide.none : BorderSide(color: colors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: padding == null
            ? child
            : Padding(padding: padding!, child: child),
      ),
    );
  }
}

/// A small label in a pill.
class _Tag extends StatelessWidget {
  const _Tag({required this.label, this.onHero = false});

  final String label;
  final bool onHero;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: EdgeInsetsDirectional.symmetric(horizontal: 10.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: onHero
            ? AppColors.cream.withValues(alpha: 0.14)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: onHero ? AppColors.cream : theme.colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
