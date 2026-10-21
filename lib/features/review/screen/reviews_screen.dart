import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/desktop.dart';
import '../../../core/di/injection.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/state/load_status.dart';
import '../../../domain/entities/review_card.dart';
import '../../surah_list/widgets/error_view.dart';
import '../cubit/review_cubit.dart';
import '../widgets/review_widgets.dart';

/// Every range the app is keeping for review: what is due now, then the
/// rest by the day each comes back — new, recent and kept alike.
class ReviewsScreen extends StatelessWidget {
  const ReviewsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider<ReviewCubit>(
    create: (_) => sl<ReviewCubit>()..load(),
    child: const _ReviewsView(),
  );
}

class _ReviewsView extends StatelessWidget {
  const _ReviewsView();

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
            return ListView.separated(
              padding: EdgeInsetsDirectional.only(bottom: 24.h),
              itemCount: state.items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (BuildContext context, int i) =>
                  _CardTile(item: state.items[i], now: now),
            );
          },
        ),
      ),
    );
  }
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
      title: Text(reviewRangeLabel(context, item)),
      subtitle: Padding(
        padding: EdgeInsetsDirectional.only(top: 4.h),
        child: Wrap(
          spacing: 8.w,
          runSpacing: 4.h,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            TierChip(tier: item.tier),
            Text(
              dueLabel(context, item, now),
              style: theme.textTheme.labelSmall?.copyWith(
                color: item.due
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (last != null)
              Text(
                LocaleKeys.reviewLastGrade.tr(
                  args: <String>[_gradeLabel(last)],
                ),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
      onTap: () => openReview(context, item),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            tooltip: LocaleKeys.reviewStart.tr(),
            onPressed: () => openReview(context, item),
            icon: const Icon(Icons.play_circle_outline),
          ),
          IconButton(
            tooltip: LocaleKeys.reviewForget.tr(),
            onPressed: () => _confirmForget(context),
            icon: const Icon(Icons.delete_outline),
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
