import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/desktop.dart';
import '../../../core/di/injection.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/state/load_status.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/ladder_mark.dart';
import '../../../core/widgets/panel.dart';
import '../../../data/models/memorization_progress.dart';
import '../../../data/models/surah.dart';
import '../../surah_list/widgets/error_view.dart';
import '../../surah_list/widgets/surah_row.dart' show SurahProgressRing;
import '../cubit/progress_cubit.dart';
import '../cubit/progress_state.dart';

/// One surah, ayah by ayah: where its memorization stands, said once at the
/// top, and then a cell per ayah.
///
/// A cell carries its number and its state as a tint — the state is not also
/// spelled out on every ayah, which is what made this screen three ayahs
/// wide. A dot marks an ayah that has been through a session.
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({required this.surahNumber, super.key});

  final int surahNumber;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ProgressCubit>(
      create: (_) => sl<ProgressCubit>()..load(surahNumber),
      child: const _ProgressView(),
    );
  }
}

class _ProgressView extends StatelessWidget {
  const _ProgressView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(LocaleKeys.progressTitle.tr())),
      body: BlocBuilder<ProgressCubit, ProgressScreenState>(
        builder: (BuildContext context, ProgressScreenState state) {
          if (state.status.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          final Surah? surah = state.surah;
          if (state.status.isFailure || surah == null) {
            return ErrorView(message: state.errorMessage ?? '');
          }

          final int started = state.records
              .where(
                (MemorizationProgress r) =>
                    r.status == MemorizationStatus.inProgress,
              )
              .length;

          return DesktopWidth(
            child: CustomScrollView(
              slivers: <Widget>[
                SliverPadding(
                  padding: EdgeInsetsDirectional.fromSTEB(16.w, 12.h, 16.w, 0),
                  sliver: SliverToBoxAdapter(
                    child: _Summary(
                      surah: surah,
                      memorized: state.memorizedCount,
                      started: started,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    16.w,
                    16.h,
                    16.w,
                    8.h,
                  ),
                  sliver: const SliverToBoxAdapter(child: _Legend()),
                ),
                SliverPadding(
                  padding: EdgeInsetsDirectional.symmetric(horizontal: 16.w),
                  sliver: SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 64.r,
                      mainAxisSpacing: 6.r,
                      crossAxisSpacing: 6.r,
                      mainAxisExtent: 44.r,
                    ),
                    itemCount: state.records.length,
                    itemBuilder: (BuildContext context, int index) =>
                        AyahCell(record: state.records[index]),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    16.w,
                    16.h,
                    16.w,
                    32.h,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      LocaleKeys.progressTapHint.tr(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// How much of the surah is memorized, in one card.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.surah,
    required this.memorized,
    required this.started,
  });

  final Surah surah;
  final int memorized;
  final int started;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool arabic = context.locale.languageCode == 'ar';
    final String caption = LocaleKeys.surahListProgress.tr(
      args: <String>[
        memorized.toLocalisedString(),
        surah.ayahCount.toLocalisedString(),
      ],
    );
    return AppCard(
      padding: EdgeInsetsDirectional.all(16.r),
      child: Row(
        children: <Widget>[
          SurahProgressRing(
            fraction: memorized / surah.ayahCount,
            caption: caption,
            diameter: 48.r,
          ),
          SizedBox(width: 14.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  arabic ? surah.nameAr : surah.nameEn,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  caption,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (started > 0)
                  Text(
                    LocaleKeys.progressInProgressCount.tr(
                      args: <String>[started.toLocalisedString()],
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          LadderMark(
            current: memorized == 0
                ? 0
                : memorized >= surah.ayahCount
                ? 4
                : (memorized * 4 / surah.ayahCount).floor().clamp(1, 3),
          ),
        ],
      ),
    );
  }
}

/// What the three tints mean, said once instead of on every ayah.
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    Widget item(Color? fill, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 12.r,
          height: 12.r,
          decoration: BoxDecoration(
            color: fill ?? theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(4.r),
            border: fill == null
                ? Border.all(color: theme.colorScheme.outline)
                : null,
          ),
        ),
        SizedBox(width: 6.w),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    return Wrap(
      spacing: 14.w,
      runSpacing: 6.h,
      children: <Widget>[
        item(
          _tint(context, MemorizationStatus.memorized),
          LocaleKeys.progressStatusMemorized.tr(),
        ),
        item(
          _tint(context, MemorizationStatus.inProgress),
          LocaleKeys.progressStatusInProgress.tr(),
        ),
        item(null, LocaleKeys.progressStatusNotStarted.tr()),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 5.r,
              height: 5.r,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant,
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(width: 6.w),
            Text(
              LocaleKeys.progressDrilled.tr(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The tint a state is drawn in — a wash of the status colour, so the number
/// on it stays the page's own text colour.
Color? _tint(BuildContext context, MemorizationStatus status) {
  final ColorScheme colors = Theme.of(context).colorScheme;
  return switch (status) {
    MemorizationStatus.notStarted => null,
    MemorizationStatus.inProgress => Color.alphaBlend(
      AppColors.statusInProgress.withValues(alpha: 0.22),
      colors.surface,
    ),
    MemorizationStatus.memorized => Color.alphaBlend(
      AppColors.statusMemorized.withValues(alpha: 0.22),
      colors.surface,
    ),
  };
}

/// One ayah: its number, its state as a tint, and a tap that marks it.
class AyahCell extends StatelessWidget {
  const AyahCell({required this.record, super.key});

  final MemorizationProgress record;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color? fill = _tint(context, record.status);
    final String label = joinDetails(<String>[
      LocaleKeys.commonAyahNumber.tr(
        args: <String>[record.ayahNumber.toLocalisedString()],
      ),
      switch (record.status) {
        MemorizationStatus.notStarted => LocaleKeys.progressStatusNotStarted,
        MemorizationStatus.inProgress => LocaleKeys.progressStatusInProgress,
        MemorizationStatus.memorized => LocaleKeys.progressStatusMemorized,
      }.tr(),
    ]);

    return Semantics(
      label: label,
      button: true,
      child: Material(
        color: fill ?? theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.r),
          side: fill == null
              ? BorderSide(color: theme.colorScheme.outline)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () =>
              context.read<ProgressCubit>().toggleMemorized(record.ayahNumber),
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Text(
                record.ayahNumber.toLocalisedString(),
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: fill == null
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.onSurface,
                ),
              ),
              if (record.cumulativeRepeats > 0)
                PositionedDirectional(
                  bottom: 5.r,
                  child: Container(
                    width: 4.r,
                    height: 4.r,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant,
                      shape: BoxShape.circle,
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
