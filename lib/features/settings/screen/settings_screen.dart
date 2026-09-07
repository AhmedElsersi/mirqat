import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/localization/locale_keys.dart';
import '../../../core/state/load_status.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/reciter.dart';
import '../../../domain/entities/session_config.dart';
import '../../session_setup/widgets/setup_controls.dart';
import '../cubit/settings_cubit.dart';
import '../cubit/settings_state.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(LocaleKeys.settingsTitle.tr())),
      body: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (BuildContext context, SettingsState state) {
          if (state.status.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final SettingsCubit cubit = context.read<SettingsCubit>();
          final AppSettings settings = state.settings;

          return ListView(
            padding: EdgeInsetsDirectional.all(16.r),
            children: <Widget>[
              SetupSection(
                label: LocaleKeys.settingsReciter.tr(),
                child: RadioGroup<String>(
                  groupValue:
                      settings.reciterId ??
                      (state.reciters.isEmpty ? null : state.reciters.first.id),
                  onChanged: (String? id) {
                    if (id != null) cubit.setReciter(id);
                  },
                  child: Column(
                    children: <Widget>[
                      // A list even with one entry, so a second reciter needs
                      // no UI change (CLAUDE.md A.2 rule 2).
                      for (final Reciter reciter in state.reciters)
                        RadioListTile<String>(
                          contentPadding: EdgeInsetsDirectional.zero,
                          title: Text(reciter.nameAr),
                          subtitle: Text(reciter.nameEn),
                          value: reciter.id,
                        ),
                    ],
                  ),
                ),
              ),
              SetupSection(
                label: LocaleKeys.settingsDefaultRepeatCount.tr(),
                child: StepperField(
                  value: settings.defaultRepeatCount,
                  min: SessionConfig.minRepeatCount,
                  max: SessionConfig.maxRepeatCount,
                  onChanged: cubit.setDefaultRepeatCount,
                ),
              ),
              SetupSection(
                label: LocaleKeys.settingsDefaultConnectMode.tr(),
                child: Column(
                  children: <Widget>[
                    for (final ConnectMode mode in ConnectMode.values)
                      ConnectModeOption(
                        label: _modeLabel(mode).tr(),
                        hint: _modeHint(mode).tr(),
                        selected: settings.defaultConnectMode == mode,
                        onTap: () => cubit.setDefaultConnectMode(mode),
                      ),
                  ],
                ),
              ),
              SetupSection(
                label: LocaleKeys.settingsTheme.tr(),
                child: RadioGroup<AppThemeMode>(
                  groupValue: settings.themeMode,
                  onChanged: (AppThemeMode? m) {
                    if (m != null) cubit.setThemeMode(m);
                  },
                  child: Column(
                    children: <Widget>[
                      for (final AppThemeMode mode in AppThemeMode.values)
                        RadioListTile<AppThemeMode>(
                          contentPadding: EdgeInsetsDirectional.zero,
                          title: Text(_themeLabel(mode).tr()),
                          value: mode,
                        ),
                    ],
                  ),
                ),
              ),
              SetupSection(
                label: LocaleKeys.settingsArabicFontSize.tr(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    LabelledSlider(
                      label: LocaleKeys.settingsArabicFontSize.tr(),
                      value: settings.arabicFontSize,
                      min: AppSettings.minArabicFontSize,
                      max: AppSettings.maxArabicFontSize,
                      divisions: 11,
                      valueLabel: settings.arabicFontSize.toStringAsFixed(0),
                      onChanged: (double v) =>
                          cubit.setArabicFontSize(v.roundToDouble()),
                    ),
                    SizedBox(height: 8.h),
                    _FontPreview(fontSize: settings.arabicFontSize),
                  ],
                ),
              ),
              if (state.errorMessage != null)
                Text(
                  state.errorMessage!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
            ],
          );
        },
      ),
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

  static String _themeLabel(AppThemeMode mode) => switch (mode) {
    AppThemeMode.system => LocaleKeys.settingsThemeSystem,
    AppThemeMode.light => LocaleKeys.settingsThemeLight,
    AppThemeMode.dark => LocaleKeys.settingsThemeDark,
  };
}

/// Shows the chosen size against the app name, which is the only Arabic string
/// on this screen that is not scripture.
class _FontPreview extends StatelessWidget {
  const _FontPreview({required this.fontSize});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsetsDirectional.all(12.r),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Text(
        LocaleKeys.appName.tr(),
        textAlign: TextAlign.center,
        style: AppTextStyles.ayah(fontSize: fontSize),
      ),
    );
  }
}
