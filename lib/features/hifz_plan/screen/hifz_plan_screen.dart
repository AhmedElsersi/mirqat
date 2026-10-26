import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../core/desktop.dart';
import '../../../core/di/injection.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/state/load_status.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/ayah_end_field.dart';
import '../../../core/widgets/ladder_mark.dart';
import '../../../core/widgets/panel.dart';
import '../../../core/widgets/range_label.dart';
import '../../../core/widgets/session_controls.dart';
import '../../../data/models/surah.dart';
import '../../../domain/engine/hifz_planner.dart';
import '../../../domain/entities/ayah_ref.dart';
import '../../../domain/entities/hifz_plan.dart';
import '../../mushaf/mushaf_args.dart';
import '../../session/session_request.dart';
import '../../surah_list/widgets/error_view.dart';
import '../../surah_list/widgets/surah_row.dart' show NumberDiamond;
import '../cubit/hifz_plan_cubit.dart';

/// "Memorize from here to there in so many days": made here, and followed
/// here.
///
/// Following it, the day's portion is the one prominent thing on the screen,
/// with one button; the portions already finished fold away behind a row, so
/// a sixty-day plan is not sixty rows of past work with today's among them.
class HifzPlanScreen extends StatelessWidget {
  const HifzPlanScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider<HifzPlanCubit>(
    create: (_) => sl<HifzPlanCubit>()..load(),
    child: const _HifzPlanView(),
  );
}

class _HifzPlanView extends StatelessWidget {
  const _HifzPlanView();

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<HifzPlanCubit, HifzPlanState>(
    builder: (BuildContext context, HifzPlanState state) {
      final HifzPlan? plan = state.plan;
      return Scaffold(
        appBar: AppBar(
          title: Text(
            plan == null ? LocaleKeys.planNew.tr() : LocaleKeys.planTitle.tr(),
          ),
          actions: <Widget>[
            if (plan != null)
              PopupMenuButton<void>(
                tooltip: LocaleKeys.commonMore.tr(),
                itemBuilder: (BuildContext context) => <PopupMenuEntry<void>>[
                  PopupMenuItem<void>(
                    onTap: () =>
                        _confirmDelete(context, context.read<HifzPlanCubit>()),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.delete_outline),
                        SizedBox(width: 10.w),
                        Text(LocaleKeys.planDelete.tr()),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
        body: DesktopWidth(
          child: state.status.isLoading
              ? const Center(child: CircularProgressIndicator())
              : state.status.isFailure
              ? ErrorView(
                  message: state.errorMessage ?? '',
                  onRetry: () => context.read<HifzPlanCubit>().load(),
                )
              : plan == null
              ? _MakePlan(state: state)
              : _FollowPlan(state: state, plan: plan),
        ),
      );
    },
  );
}

/// Opens the reading view on [portion] with a session set up and playing:
/// the reader's own drill, the way a new portion is learned.
Future<void> openPortion(BuildContext context, Portion portion) =>
    context.pushNamed<void>(
      AppRoutes.mushafName,
      extra: MushafArgs(
        initialAyah: portion.from,
        session: SessionRequest(
          from: portion.from,
          to: portion.to,
          autostart: true,
        ),
      ),
    );

String portionLabel(BuildContext context, HifzPlanState state, Portion p) {
  final Surah? a = state.surah(p.from.surah);
  final Surah? b = state.surah(p.to.surah);
  if (a == null || b == null) return '${p.from} – ${p.to}';
  return rangeLabel(context, from: p.from, to: p.to, fromSurah: a, toSurah: b);
}

Future<void> _confirmDelete(BuildContext context, HifzPlanCubit cubit) async {
  final bool? yes = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialog) => AlertDialog(
      content: Text(LocaleKeys.planDeleteConfirm.tr()),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(false),
          child: Text(LocaleKeys.commonCancel.tr()),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialog).pop(true),
          child: Text(LocaleKeys.planDelete.tr()),
        ),
      ],
    ),
  );
  if (yes ?? false) await cubit.delete();
}

/// Setting a plan up: what to memorize, in how many days, and what that
/// comes to — said in one line above the button.
class _MakePlan extends StatelessWidget {
  const _MakePlan({required this.state});

  final HifzPlanState state;

  /// The lengths a plan is usually given, so the common choice is one tap.
  static const List<int> _common = <int>[7, 30, 60, 90];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final HifzPlanCubit cubit = context.read<HifzPlanCubit>();
    final int ayahs = state.draftAyahs;
    final int perDay = (ayahs / state.days).ceil();

    return ListView(
      padding: EdgeInsetsDirectional.fromSTEB(16.w, 12.h, 16.w, 32.h),
      children: <Widget>[
        Text(
          LocaleKeys.planIntro.tr(),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        FieldLabel(LocaleKeys.planRange.tr()),
        // The range as two rows, each a tap from its surah and ayah.
        AppCard(
          padding: EdgeInsetsDirectional.zero,
          child: Column(
            children: <Widget>[
              _RangeEndRow(
                icon: Icons.vertical_align_bottom,
                label: LocaleKeys.sessionSetupFrom.tr(),
                surahs: state.surahs,
                value: state.from,
                onChanged: cubit.setFrom,
                isEnd: false,
              ),
              const Divider(height: 1),
              _RangeEndRow(
                icon: Icons.vertical_align_top,
                label: LocaleKeys.sessionSetupTo.tr(),
                surahs: <Surah>[
                  for (final Surah s in state.surahs)
                    if (s.number >= state.from.surah) s,
                ],
                value: state.to,
                onChanged: cubit.setTo,
                isEnd: true,
              ),
            ],
          ),
        ),
        FieldLabel(LocaleKeys.planDays.tr()),
        StepperField(
          value: state.days,
          min: 1,
          max: HifzPlanner.maxDays,
          editable: true,
          formatValue: (int v) => v.toLocalisedString(),
          onChanged: cubit.setDays,
        ),
        SizedBox(height: 10.h),
        Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          children: <Widget>[
            for (final int days in _common)
              ChoiceChip(
                selected: state.days == days,
                onSelected: (_) => cubit.setDays(days),
                label: Text(
                  LocaleKeys.planDaysCount.tr(
                    args: <String>[days.toLocalisedString()],
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: 18.h),
        AppCard(
          padding: EdgeInsetsDirectional.all(16.r),
          child: Column(
            children: <Widget>[
              Text(
                LocaleKeys.planPreview.tr(
                  args: <String>[
                    ayahs.toLocalisedString(),
                    // Fewer ayahs than days: one a day, and the plan is that
                    // many days long.
                    (ayahs < state.days ? 1 : perDay).toLocalisedString(),
                  ],
                ),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                LocaleKeys.planWhereItShows.tr(),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if ((state.errorMessage ?? '').isNotEmpty) ...<Widget>[
          SizedBox(height: 12.h),
          Text(
            state.errorMessage!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        SizedBox(height: 16.h),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: Size(0, 50.r)),
          onPressed: state.saving || ayahs == 0 ? null : cubit.create,
          icon: const Icon(Icons.flag_outlined),
          label: Text(LocaleKeys.planCreate.tr()),
        ),
      ],
    );
  }
}

/// Following a plan: today, then how far it has come, then its portions.
class _FollowPlan extends StatelessWidget {
  const _FollowPlan({required this.state, required this.plan});

  final HifzPlanState state;
  final HifzPlan plan;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Portion? today = plan.current;
    final List<Portion> done = plan.portions.take(plan.completed).toList();
    final List<Portion> ahead = plan.portions.skip(plan.completed + 1).toList();

    return ListView(
      padding: EdgeInsetsDirectional.fromSTEB(16.w, 12.h, 16.w, 32.h),
      children: <Widget>[
        if (today == null)
          AppCard(
            padding: EdgeInsetsDirectional.all(20.r),
            child: Row(
              children: <Widget>[
                const TileIcon(Icons.verified_outlined),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    LocaleKeys.planFinished.tr(),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
          )
        else
          _TodayPortion(state: state, plan: plan, portion: today),
        SizedBox(height: 12.h),
        AppCard(
          padding: EdgeInsetsDirectional.all(16.r),
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
                          portionLabel(
                            context,
                            state,
                            Portion(plan.from, plan.to),
                          ),
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          LocaleKeys.planAyahCount.tr(
                            args: <String>[
                              state
                                  .ayahsIn(plan.from, plan.to)
                                  .toLocalisedString(),
                            ],
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 12.w),
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
              SizedBox(height: 12.h),
              ProgressBar(
                value: plan.portions.isEmpty
                    ? 0
                    : plan.completed / plan.portions.length,
              ),
              SizedBox(height: 8.h),
              Text(
                LocaleKeys.planProgress.tr(
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
        SectionTitle(title: LocaleKeys.planPortions.tr()),
        AppCard(
          padding: EdgeInsetsDirectional.zero,
          child: Column(
            children: <Widget>[
              // What is finished is kept, not shown: a plan's past is the
              // longest part of it and the least use.
              if (done.isNotEmpty)
                ExpansionTile(
                  shape: const Border(),
                  collapsedShape: const Border(),
                  leading: TileIcon(
                    Icons.check,
                    color: theme.brightness == Brightness.dark
                        ? AppColors.sabrDark
                        : AppColors.sabrLight,
                  ),
                  title: Text(
                    LocaleKeys.planPast.tr(),
                    style: theme.textTheme.titleSmall,
                  ),
                  subtitle: Text(
                    joinDetails(<String>[
                      LocaleKeys.planPastCount.tr(
                        args: <String>[done.length.toLocalisedString()],
                      ),
                      portionLabel(
                        context,
                        state,
                        Portion(done.first.from, done.last.to),
                      ),
                    ]),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  children: <Widget>[
                    for (int i = 0; i < done.length; i++)
                      _PortionRow(
                        state: state,
                        portion: done[i],
                        day: i + 1,
                        status: _PortionState.done,
                      ),
                  ],
                ),
              if (done.isNotEmpty && today != null) const Divider(height: 1),
              if (today != null)
                _PortionRow(
                  state: state,
                  portion: today,
                  day: plan.completed + 1,
                  status: _PortionState.today,
                ),
              for (int i = 0; i < ahead.length; i++) ...<Widget>[
                const Divider(height: 1),
                _PortionRow(
                  state: state,
                  portion: ahead[i],
                  day: plan.completed + 2 + i,
                  status: _PortionState.ahead,
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: 14.h),
        AppNote(LocaleKeys.planHowItMoves.tr()),
      ],
    );
  }
}

/// The day's portion: the screen's one prominent card, with one button.
class _TodayPortion extends StatelessWidget {
  const _TodayPortion({
    required this.state,
    required this.plan,
    required this.portion,
  });

  final HifzPlanState state;
  final HifzPlan plan;
  final Portion portion;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
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
            Text(
              LocaleKeys.planToday.tr(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: onHero.withValues(alpha: 0.78),
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              portionLabel(context, state, portion),
              style: theme.textTheme.titleLarge?.copyWith(
                color: onHero,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              LocaleKeys.planTodayLine.tr(
                args: <String>[
                  state.ayahsIn(portion.from, portion.to).toLocalisedString(),
                  (plan.completed + 1).toLocalisedString(),
                  plan.portions.length.toLocalisedString(),
                ],
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: onHero.withValues(alpha: 0.78),
              ),
            ),
            SizedBox(height: 16.h),
            Row(
              children: <Widget>[
                LadderMark(
                  current: 2,
                  color: onHero.withValues(alpha: 0.18),
                  doneColor: AppColors.rungDoneOnHero,
                ),
                const Spacer(),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: onHero,
                    foregroundColor: AppColors.forest,
                    minimumSize: Size(0, 48.r),
                  ),
                  onPressed: () => openPortion(context, portion),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(LocaleKeys.planStart.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _PortionState { done, today, ahead }

class _PortionRow extends StatelessWidget {
  const _PortionRow({
    required this.state,
    required this.portion,
    required this.day,
    required this.status,
  });

  final HifzPlanState state;
  final Portion portion;
  final int day;
  final _PortionState status;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool today = status == _PortionState.today;
    return Container(
      color: today ? AppColors.gold.withValues(alpha: 0.2) : null,
      child: ListTile(
        leading: status == _PortionState.done
            ? TileIcon(
                Icons.check,
                color: theme.brightness == Brightness.dark
                    ? AppColors.sabrDark
                    : AppColors.sabrLight,
              )
            : NumberDiamond(number: day),
        title: Text(
          today
              ? LocaleKeys.tabsToday.tr()
              : LocaleKeys.planDay.tr(args: <String>[day.toLocalisedString()]),
          style: theme.textTheme.titleSmall,
        ),
        subtitle: Text(
          portionLabel(context, state, portion),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: today
            ? PlayButton(
                tooltip: LocaleKeys.planStart.tr(),
                onPressed: () => openPortion(context, portion),
              )
            : Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
        onTap: () => openPortion(context, portion),
      ),
    );
  }
}

/// One end of the new plan's range as a row of a list — «من» over «سورة
/// النبأ، الآية ١» — that opens the surah and ayah pickers.
class _RangeEndRow extends StatelessWidget {
  const _RangeEndRow({
    required this.icon,
    required this.label,
    required this.surahs,
    required this.value,
    required this.onChanged,
    required this.isEnd,
  });

  final IconData icon;
  final String label;
  final List<Surah> surahs;
  final AyahRef value;
  final ValueChanged<AyahRef> onChanged;
  final bool isEnd;

  Future<void> _pick(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _EndPicker(
      label: label,
      surahs: surahs,
      initial: value,
      onChanged: onChanged,
      isEnd: isEnd,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Surah? surah = surahs
        .where((Surah s) => s.number == value.surah)
        .firstOrNull;
    final String name = surah == null
        ? ''
        : context.locale.languageCode == 'ar'
        ? surah.nameAr
        : surah.nameEn;
    return ListTile(
      onTap: () => _pick(context),
      leading: TileIcon(icon),
      title: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      subtitle: Text(
        joinDetails(<String>[
          LocaleKeys.mushafSurahLabel.tr(args: <String>[name]),
          LocaleKeys.commonAyahNumber.tr(
            args: <String>[value.ayah.toLocalisedString()],
          ),
        ]),
        style: theme.textTheme.titleSmall,
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// The surah and the ayah of one end, applied as they are picked.
class _EndPicker extends StatefulWidget {
  const _EndPicker({
    required this.label,
    required this.surahs,
    required this.initial,
    required this.onChanged,
    required this.isEnd,
  });

  final String label;
  final List<Surah> surahs;
  final AyahRef initial;
  final ValueChanged<AyahRef> onChanged;
  final bool isEnd;

  @override
  State<_EndPicker> createState() => _EndPickerState();
}

class _EndPickerState extends State<_EndPicker> {
  late AyahRef _value = widget.initial;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        16.w,
        0,
        16.w,
        12.h + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AyahEndField(
            label: widget.label,
            surahs: widget.surahs,
            value: _value,
            isEnd: widget.isEnd,
            onChanged: (AyahRef ref) {
              setState(() => _value = ref);
              widget.onChanged(ref);
            },
          ),
          SizedBox(height: 16.h),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: Size(0, 48.r)),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(LocaleKeys.commonDone.tr()),
          ),
        ],
      ),
    ),
  );
}
