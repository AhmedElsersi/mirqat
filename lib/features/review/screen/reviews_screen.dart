import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/desktop.dart';
import '../../../core/di/injection.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/state/load_status.dart';
import '../../../core/widgets/ladder_mark.dart';
import '../../../core/widgets/panel.dart';
import '../../../domain/entities/review_card.dart';
import '../../surah_list/widgets/error_view.dart';
import '../cubit/review_cubit.dart';
import '../widgets/review_widgets.dart';

/// Every range the app is keeping for review: what is due now, then the rest
/// by the day each comes back.
///
/// The three rungs count at the top and narrow the list when tapped; each row
/// then carries one obvious action — start this review — and keeps "forget
/// it" behind the row's own menu, where an action that undoes weeks of work
/// belongs.
class ReviewsScreen extends StatelessWidget {
  const ReviewsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider<ReviewCubit>(
    create: (_) => sl<ReviewCubit>()..load(),
    child: const _ReviewsView(),
  );
}

class _ReviewsView extends StatefulWidget {
  const _ReviewsView();

  @override
  State<_ReviewsView> createState() => _ReviewsViewState();
}

class _ReviewsViewState extends State<_ReviewsView> {
  /// Null is every tier: the screen opens on the whole schedule.
  ReviewTier? _tier;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(LocaleKeys.reviewTitle.tr())),
      body: DesktopWidth(
        child: BlocBuilder<ReviewCubit, ReviewState>(
          builder: (BuildContext context, ReviewState state) {
            if (state.status.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.status.isFailure) {
              return ErrorView(
                message: state.errorMessage ?? '',
                onRetry: () => context.read<ReviewCubit>().load(),
              );
            }
            if (state.items.isEmpty) {
              return Center(
                child: Padding(
                  padding: EdgeInsetsDirectional.all(32.r),
                  child: Text(
                    LocaleKeys.reviewEmpty.tr(),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            final DateTime now = context.read<ReviewCubit>().clock();
            final List<ReviewItem> shown = <ReviewItem>[
              for (final ReviewItem i in state.items)
                if (_tier == null || i.tier == _tier) i,
            ];
            final List<ReviewItem> due = <ReviewItem>[
              for (final ReviewItem i in shown)
                if (i.due) i,
            ];
            final List<ReviewItem> later = <ReviewItem>[
              for (final ReviewItem i in shown)
                if (!i.due) i,
            ];

            return ListView(
              padding: EdgeInsetsDirectional.fromSTEB(16.w, 12.h, 16.w, 24.h),
              children: <Widget>[
                Row(
                  children: <Widget>[
                    for (final ReviewTier tier
                        in ReviewTier.values) ...<Widget>[
                      if (tier != ReviewTier.values.first)
                        SizedBox(width: 10.w),
                      Expanded(
                        child: _TierCard(
                          tier: tier,
                          count: state.items
                              .where((ReviewItem i) => i.tier == tier)
                              .length,
                          chosen: _tier == tier,
                          onTap: () => setState(
                            () => _tier = _tier == tier ? null : tier,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (due.isNotEmpty) ...<Widget>[
                  SectionTitle(
                    title: LocaleKeys.reviewDueToday.tr(),
                    trailing: due.length.toLocalisedString(),
                  ),
                  _Group(items: due, now: now),
                ],
                if (later.isNotEmpty) ...<Widget>[
                  SectionTitle(title: LocaleKeys.reviewLater.tr()),
                  _Group(items: later, now: now),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One rung, how many passages stand on it, and a tap that shows only those.
class _TierCard extends StatelessWidget {
  const _TierCard({
    required this.tier,
    required this.count,
    required this.chosen,
    required this.onTap,
  });

  final ReviewTier tier;
  final int count;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      padding: EdgeInsetsDirectional.symmetric(vertical: 12.h),
      border: chosen ? theme.colorScheme.primary : null,
      child: Column(
        children: <Widget>[
          Text(
            count.toLocalisedString(),
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
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.items, required this.now});

  final List<ReviewItem> items;
  final DateTime now;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: EdgeInsetsDirectional.zero,
    child: Column(
      children: <Widget>[
        for (final ReviewItem item in items) ...<Widget>[
          if (item != items.first) const Divider(height: 1),
          _CardTile(item: item, now: now),
        ],
      ],
    ),
  );
}

class _CardTile extends StatelessWidget {
  const _CardTile({required this.item, required this.now});

  final ReviewItem item;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Grade? last = item.card.lastGrade;
    return ListTile(
      // The ladder says how far the passage has climbed: new, recent, kept.
      leading: LadderMark(
        current: switch (item.tier) {
          ReviewTier.sabaq => 1,
          ReviewTier.sabqi => 2,
          ReviewTier.manzil => 3,
        },
      ),
      title: Text(
        reviewRangeLabel(context, item),
        style: theme.textTheme.titleSmall,
      ),
      subtitle: Text(
        joinDetails(<String>[
          tierLabel(item.tier),
          dueLabel(context, item, now),
          if (last != null)
            LocaleKeys.reviewLastGrade.tr(args: <String>[_gradeLabel(last)]),
        ]),
      ),
      onTap: () => openReview(context, item),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton.filledTonal(
            tooltip: LocaleKeys.reviewStart.tr(),
            onPressed: () => openReview(context, item),
            icon: const Icon(Icons.play_arrow),
          ),
          PopupMenuButton<void>(
            tooltip: LocaleKeys.commonMore.tr(),
            itemBuilder: (BuildContext context) => <PopupMenuEntry<void>>[
              PopupMenuItem<void>(
                onTap: () => _confirmForget(context),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.delete_outline),
                    SizedBox(width: 10.w),
                    Text(LocaleKeys.reviewForget.tr()),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _gradeLabel(Grade g) => switch (g) {
    Grade.solid => LocaleKeys.reviewGradeSolid.tr(),
    Grade.shaky => LocaleKeys.reviewGradeShaky.tr(),
    Grade.forgot => LocaleKeys.reviewGradeForgot.tr(),
  };

  Future<void> _confirmForget(BuildContext context) async {
    final ReviewCubit cubit = context.read<ReviewCubit>();
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialog) => AlertDialog(
        content: Text(LocaleKeys.reviewForgetConfirm.tr()),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(LocaleKeys.commonCancel.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(LocaleKeys.reviewForget.tr()),
          ),
        ],
      ),
    );
    if (yes ?? false) await cubit.delete(item);
  }
}
