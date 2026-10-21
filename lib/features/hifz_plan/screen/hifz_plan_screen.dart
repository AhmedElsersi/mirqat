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
import '../../../core/widgets/ayah_end_field.dart';
import '../../../core/widgets/range_label.dart';
import '../../../core/widgets/session_controls.dart';
import '../../../core/widgets/settings_card.dart';
import '../../../data/models/surah.dart';
import '../../../domain/engine/hifz_planner.dart';
import '../../../domain/entities/hifz_plan.dart';
import '../../mushaf/mushaf_args.dart';
import '../../session/session_request.dart';
import '../../surah_list/widgets/error_view.dart';
import '../cubit/hifz_plan_cubit.dart';

/// "Memorize from here to there in so many days": made here, and followed
/// here — the portions, where the reader is in them, and the day's portion
/// one tap from a session.
class HifzPlanScreen extends StatelessWidget {
  const HifzPlanScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider<HifzPlanCubit>(
    create: (_) => sl<HifzPlanCubit>()..load(),
    child: Scaffold(
      appBar: AppBar(title: Text(LocaleKeys.planTitle.tr())),
      body: DesktopWidth(
        child: BlocBuilder<HifzPlanCubit, HifzPlanState>(
          builder: (BuildContext context, HifzPlanState state) {
            if (state.status.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.status.isFailure) {
              return ErrorView(
                message: state.errorMessage ?? '',
                onRetry: () => context.read<HifzPlanCubit>().load(),
              );
            }
            final HifzPlan? plan = state.plan;
            return plan == null
                ? _MakePlan(state: state)
                : _FollowPlan(state: state, plan: plan);
          },
        ),
      ),
    ),
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

class _MakePlan extends StatelessWidget {
  const _MakePlan({required this.state});

  final HifzPlanState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final HifzPlanCubit cubit = context.read<HifzPlanCubit>();
    final int ayahs = state.draftAyahs;
    final int perDay = (ayahs / state.days).ceil();

    return ListView(
      padding: EdgeInsetsDirectional.all(16.r),
      children: <Widget>[
        Padding(
          padding: EdgeInsetsDirectional.only(bottom: 16.h),
          child: Text(
            LocaleKeys.planIntro.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        SettingsCard(
          title: LocaleKeys.planRange.tr(),
          icon: Icons.straighten,
          children: <Widget>[
            AyahEndField(
              label: LocaleKeys.sessionSetupFrom.tr(),
              surahs: state.surahs,
              value: state.from,
              onChanged: cubit.setFrom,
              isEnd: false,
            ),
            SizedBox(height: 12.h),
            AyahEndField(
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
        SettingsCard(
          title: LocaleKeys.planDays.tr(),
          icon: Icons.calendar_month_outlined,
          children: <Widget>[
            StepperField(
              value: state.days,
              min: 1,
              max: HifzPlanner.maxDays,
              editable: true,
              formatValue: (int v) => v.toLocalisedString(),
              onChanged: cubit.setDays,
            ),
            SizedBox(height: 8.h),
            Text(
              LocaleKeys.planPreview.tr(
                args: <String>[
                  ayahs.toLocalisedString(),
                  // Fewer ayahs than days: one a day, and the plan is that
                  // many days long.
                  (ayahs < state.days ? 1 : perDay).toLocalisedString(),
                ],
              ),
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
        if ((state.errorMessage ?? '').isNotEmpty)
          Text(
            state.errorMessage!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        SizedBox(height: 8.h),
        FilledButton.icon(
          onPressed: state.saving || ayahs == 0 ? null : cubit.create,
          icon: const Icon(Icons.flag_circle_outlined),
          label: Text(LocaleKeys.planCreate.tr()),
        ),
      ],
    );
  }
}

class _FollowPlan extends StatelessWidget {
  const _FollowPlan({required this.state, required this.plan});

  final HifzPlanState state;
  final HifzPlan plan;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final HifzPlanCubit cubit = context.read<HifzPlanCubit>();
    final Portion? today = plan.current;

    return ListView(
      padding: EdgeInsetsDirectional.all(16.r),
      children: <Widget>[
        Text(
          portionLabel(context, state, Portion(plan.from, plan.to)),
          style: theme.textTheme.titleMedium,
        ),
        SizedBox(height: 8.h),
        LinearProgressIndicator(
          value: plan.completed / plan.portions.length,
          minHeight: 8.h,
          borderRadius: BorderRadius.circular(4.r),
        ),
        SizedBox(height: 6.h),
        Text(
          LocaleKeys.planProgress.tr(
            args: <String>[
              plan.completed.toLocalisedString(),
              plan.portions.length.toLocalisedString(),
            ],
          ),
          style: theme.textTheme.bodySmall,
        ),
        SizedBox(height: 16.h),
        if (today == null)
          Card(
            child: Padding(
              padding: EdgeInsetsDirectional.all(16.r),
              child: Text(
                LocaleKeys.planFinished.tr(),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall,
              ),
            ),
          )
        else
          Card(
            color: theme.colorScheme.primary.withValues(alpha: 0.08),
            child: ListTile(
              leading: Icon(Icons.today, color: theme.colorScheme.primary),
              title: Text(LocaleKeys.planToday.tr()),
              subtitle: Text(portionLabel(context, state, today)),
              trailing: FilledButton(
                onPressed: () => openPortion(context, today),
                child: Text(LocaleKeys.planStart.tr()),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsetsDirectional.only(top: 8.h, bottom: 4.h),
          child: Text(
            LocaleKeys.planHowItMoves.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        SizedBox(height: 8.h),
        for (int i = 0; i < plan.portions.length; i++)
          ListTile(
            dense: true,
            contentPadding: EdgeInsetsDirectional.zero,
            leading: Icon(
              i < plan.completed
                  ? Icons.check_circle
                  : i == plan.completed
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: i < plan.completed
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            title: Text(
              LocaleKeys.planDay.tr(
                args: <String>[(i + 1).toLocalisedString()],
              ),
            ),
            subtitle: Text(portionLabel(context, state, plan.portions[i])),
            onTap: () => openPortion(context, plan.portions[i]),
          ),
        SizedBox(height: 16.h),
        OutlinedButton.icon(
          onPressed: () => _confirmDelete(context, cubit),
          icon: const Icon(Icons.delete_outline),
          label: Text(LocaleKeys.planDelete.tr()),
        ),
      ],
    );
  }

  static Future<void> _confirmDelete(
    BuildContext context,
    HifzPlanCubit cubit,
  ) async {
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
}
