import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/injection.dart';
import '../../../core/extensions/duration_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/state/load_status.dart';
import '../../../domain/entities/session_config.dart';
import '../../player/player_args.dart';
import '../../surah_list/widgets/error_view.dart';
import '../cubit/session_setup_cubit.dart';
import '../cubit/session_setup_state.dart';
import '../widgets/setup_controls.dart';

class SessionSetupScreen extends StatelessWidget {
  const SessionSetupScreen({required this.surahNumber, super.key});

  final int surahNumber;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<SessionSetupCubit>(
      create: (_) => sl<SessionSetupCubit>()..load(surahNumber),
      child: const _SessionSetupView(),
    );
  }
}

class _SessionSetupView extends StatelessWidget {
  const _SessionSetupView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(LocaleKeys.sessionSetupTitle.tr())),
      body: BlocBuilder<SessionSetupCubit, SessionSetupState>(
        builder: (BuildContext context, SessionSetupState state) {
          if (state.status.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.status.isFailure || state.config == null) {
            return ErrorView(message: state.errorMessage ?? '');
          }
          return _SetupForm(state: state);
        },
      ),
    );
  }
}

class _SetupForm extends StatelessWidget {
  const _SetupForm({required this.state});

  final SessionSetupState state;

  @override
  Widget build(BuildContext context) {
    final SessionSetupCubit cubit = context.read<SessionSetupCubit>();
    final SessionConfig config = state.config!;
    final int ayahCount = state.surah!.ayahCount;

    return Column(
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsetsDirectional.all(16.r),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SetupSection(
                  label: LocaleKeys.sessionSetupRange.tr(),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: _LabelledStepper(
                          label: LocaleKeys.sessionSetupFrom.tr(),
                          value: config.startAyah,
                          min: 1,
                          max: ayahCount,
                          onChanged: (int v) => cubit.setRange(startAyah: v),
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: _LabelledStepper(
                          label: LocaleKeys.sessionSetupTo.tr(),
                          value: config.endAyah,
                          min: 1,
                          max: ayahCount,
                          onChanged: (int v) => cubit.setRange(endAyah: v),
                        ),
                      ),
                    ],
                  ),
                ),
                SetupSection(
                  label: LocaleKeys.sessionSetupRepeatCount.tr(),
                  child: StepperField(
                    value: config.repeatCount,
                    min: SessionConfig.minRepeatCount,
                    max: SessionConfig.maxRepeatCount,
                    onChanged: cubit.setRepeatCount,
                  ),
                ),
                SetupSection(
                  label: LocaleKeys.sessionSetupConnectMode.tr(),
                  child: Column(
                    children: <Widget>[
                      for (final ConnectMode mode in ConnectMode.values)
                        ConnectModeOption(
                          label: _modeLabel(mode).tr(),
                          hint: _modeHint(mode).tr(),
                          selected: config.connectMode == mode,
                          onTap: () => cubit.setConnectMode(mode),
                        ),
                    ],
                  ),
                ),
                if (state.reciter!.hasIstiadhah)
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsetsDirectional.zero,
                    title: Text(LocaleKeys.sessionSetupPlayIstiadhah.tr()),
                    value: config.playIstiadhah,
                    onChanged: cubit.setPlayIstiadhah,
                  ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsetsDirectional.zero,
                  title: Text(LocaleKeys.sessionSetupFinalFullPass.tr()),
                  value: config.finalFullPass,
                  onChanged: cubit.setFinalFullPass,
                ),
                _AdvancedPanel(config: config, cubit: cubit),
              ],
            ),
          ),
        ),
        _StartBar(state: state),
      ],
    );
  }

  static String _modeLabel(ConnectMode mode) => switch (mode) {
    ConnectMode.cumulative => LocaleKeys.sessionSetupConnectCumulative,
    ConnectMode.pairwise => LocaleKeys.sessionSetupConnectPairwise,
    ConnectMode.none => LocaleKeys.sessionSetupConnectNone,
  };

  static String _modeHint(ConnectMode mode) => switch (mode) {
    ConnectMode.cumulative => LocaleKeys.sessionSetupConnectCumulativeHint,
    ConnectMode.pairwise => LocaleKeys.sessionSetupConnectPairwiseHint,
    ConnectMode.none => LocaleKeys.sessionSetupConnectNoneHint,
  };
}

class _LabelledStepper extends StatelessWidget {
  const _LabelledStepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        SizedBox(height: 4.h),
        StepperField(value: value, min: min, max: max, onChanged: onChanged),
      ],
    );
  }
}

class _AdvancedPanel extends StatelessWidget {
  const _AdvancedPanel({required this.config, required this.cubit});

  final SessionConfig config;
  final SessionSetupCubit cubit;

  @override
  Widget build(BuildContext context) {
    String ms(int value) =>
        LocaleKeys.sessionSetupMilliseconds.tr(args: <String>['$value']);

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsetsDirectional.zero,
        childrenPadding: EdgeInsetsDirectional.only(bottom: 8.h),
        title: Text(LocaleKeys.sessionSetupAdvanced.tr()),
        children: <Widget>[
          LabelledSlider(
            label: LocaleKeys.sessionSetupIntraBlockPause.tr(),
            value: config.intraBlockPauseMs.toDouble(),
            min: 0,
            max: 2000,
            divisions: 20,
            valueLabel: ms(config.intraBlockPauseMs),
            onChanged: (double v) => cubit.setIntraBlockPause(v.round()),
          ),
          LabelledSlider(
            label: LocaleKeys.sessionSetupBetweenRepeatPause.tr(),
            value: config.betweenRepeatPauseMs.toDouble(),
            min: 0,
            max: 3000,
            divisions: 30,
            valueLabel: ms(config.betweenRepeatPauseMs),
            onChanged: (double v) => cubit.setBetweenRepeatPause(v.round()),
          ),
          LabelledSlider(
            label: LocaleKeys.sessionSetupBetweenStepsPause.tr(),
            value: config.betweenStepsPauseMs.toDouble(),
            min: 0,
            max: 5000,
            divisions: 25,
            valueLabel: ms(config.betweenStepsPauseMs),
            onChanged: (double v) => cubit.setBetweenStepsPause(v.round()),
          ),
          LabelledSlider(
            label: LocaleKeys.sessionSetupPlaybackSpeed.tr(),
            value: config.playbackSpeed,
            min: SessionConfig.minPlaybackSpeed,
            max: SessionConfig.maxPlaybackSpeed,
            divisions: 10,
            valueLabel: '${config.playbackSpeed.toStringAsFixed(2)}x',
            onChanged: (double v) =>
                cubit.setPlaybackSpeed((v * 20).round() / 20),
          ),
        ],
      ),
    );
  }
}

class _StartBar extends StatelessWidget {
  const _StartBar({required this.state});

  final SessionSetupState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsetsDirectional.all(16.r),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (state.configError != null)
              Padding(
                padding: EdgeInsetsDirectional.only(bottom: 12.h),
                child: Text(
                  state.configError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
              )
            else if (state.plan != null)
              SessionSummary(
                stepCount: state.plan!.stepCount,
                unitCount: state.plan!.unitCount,
                duration: (state.estimatedDuration ?? Duration.zero).localized,
              ),
            SizedBox(height: 12.h),
            SizedBox(
              width: double.infinity,
              height: 52.h,
              child: FilledButton(
                onPressed: state.canStart
                    ? () => context.pushNamed(
                        AppRoutes.playerName,
                        extra: PlayerArgs(
                          plan: state.plan!,
                          surah: state.surah!,
                          reciter: state.reciter!,
                          ayahs: state.ayahs,
                        ),
                      )
                    : null,
                child: Text(LocaleKeys.sessionSetupStart.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
