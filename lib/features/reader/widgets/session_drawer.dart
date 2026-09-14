import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/extensions/duration_extensions.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/widgets/reciter_avatar.dart';
import '../../../core/widgets/session_controls.dart';
import '../../../data/models/reciter.dart';
import '../../../data/models/surah.dart';
import '../../../domain/entities/session_config.dart';
import '../cubit/reader_cubit.dart';
import '../cubit/reader_state.dart';

/// Per-session overrides, as a trailing-edge drawer beside the text.
///
/// Everything here is scratch: edits land on the live config and are gone when
/// the screen closes. «حفظ كافتراضي» is the only thing that writes to storage,
/// which is what keeps a one-off long session from quietly becoming the
/// reader's new normal.
class SessionDrawer extends StatelessWidget {
  const SessionDrawer({required this.state, super.key});

  final ReaderState state;

  @override
  Widget build(BuildContext context) {
    final ReaderCubit cubit = context.read<ReaderCubit>();
    final SessionConfig? config = state.config;
    final Surah? surah = state.surah;
    final Reciter? reciter = state.reciter;
    if (config == null || surah == null || reciter == null) {
      return const Drawer(child: SizedBox.shrink());
    }

    final ThemeData theme = Theme.of(context);

    return Drawer(
      // Drawers default to 304dp; the sliders and steppers in here need the
      // room, but not more than most of the screen on a small phone.
      width: MediaQuery.sizeOf(context).width.clamp(0, 360.w),
      child: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: EdgeInsetsDirectional.all(16.r),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      LocaleKeys.readerSessionSettings.tr(),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: LocaleKeys.commonClose.tr(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: EdgeInsetsDirectional.all(16.r),
                children: <Widget>[
                  _ReciterLine(reciter: reciter),
                  SizedBox(height: 20.h),
                  SetupSection(
                    label: LocaleKeys.sessionSetupRange.tr(),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: _LabelledStepper(
                            label: LocaleKeys.sessionSetupFrom.tr(),
                            value: config.startAyah,
                            min: 1,
                            max: surah.ayahCount,
                            onChanged: (int v) => cubit.setRange(startAyah: v),
                          ),
                        ),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: _LabelledStepper(
                            label: LocaleKeys.sessionSetupTo.tr(),
                            value: config.endAyah,
                            min: 1,
                            max: surah.ayahCount,
                            onChanged: (int v) => cubit.setRange(endAyah: v),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SessionTuningControls(
                    repeatCount: config.repeatCount,
                    connectMode: config.connectMode,
                    intraBlockPauseMs: config.intraBlockPauseMs,
                    betweenRepeatPauseMs: config.betweenRepeatPauseMs,
                    betweenStepsPauseMs: config.betweenStepsPauseMs,
                    playbackSpeed: config.playbackSpeed,
                    onRepeatCount: cubit.setRepeatCount,
                    onConnectMode: cubit.setConnectMode,
                    onIntraBlockPause: cubit.setIntraBlockPause,
                    onBetweenRepeatPause: cubit.setBetweenRepeatPause,
                    onBetweenStepsPause: cubit.setBetweenStepsPause,
                    onPlaybackSpeed: cubit.setPlaybackSpeed,
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsetsDirectional.zero,
                    title: Text(LocaleKeys.sessionSetupFinalFullPass.tr()),
                    value: config.finalFullPass,
                    onChanged: cubit.setFinalFullPass,
                  ),
                  if (reciter.hasIstiadhah)
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsetsDirectional.zero,
                      title: Text(LocaleKeys.sessionSetupPlayIstiadhah.tr()),
                      value: config.playIstiadhah,
                      onChanged: cubit.setPlayIstiadhah,
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            _DrawerFooter(state: state, cubit: cubit),
          ],
        ),
      ),
    );
  }
}

class _ReciterLine extends StatelessWidget {
  const _ReciterLine({required this.reciter});

  final Reciter reciter;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      children: <Widget>[
        ReciterAvatar(reciter: reciter, diameter: 40),
        SizedBox(width: 12.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                LocaleKeys.settingsReciter.tr(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(reciter.nameAr, style: theme.textTheme.bodyLarge),
            ],
          ),
        ),
      ],
    );
  }
}

/// The measured summary, then the two actions.
class _DrawerFooter extends StatelessWidget {
  const _DrawerFooter({required this.state, required this.cubit});

  final ReaderState state;
  final ReaderCubit cubit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: EdgeInsetsDirectional.all(16.r),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (state.configError != null)
            Text(
              state.configError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
              textAlign: TextAlign.center,
            )
          else if (state.plan != null)
            // Step and recitation counts come from the built plan, and the
            // duration from real clip lengths — never an estimate from an
            // average ayah.
            SessionSummary(
              stepCount: state.plan!.stepCount,
              unitCount: state.plan!.unitCount,
              duration: (state.estimatedDuration ?? Duration.zero).localized,
            ),
          SizedBox(height: 12.h),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: cubit.resetToDefaults,
                  child: Text(LocaleKeys.readerResetDefaults.tr()),
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: FilledButton.tonal(
                  onPressed: cubit.saveAsDefaults,
                  child: Text(LocaleKeys.readerSaveAsDefault.tr()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
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
        StepperField(
          value: value,
          min: min,
          max: max,
          formatValue: (int v) => v.toLocalisedString(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
