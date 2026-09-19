import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/state/load_status.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/ayah_text.dart';
import '../../../core/widgets/reciter_avatar.dart';
import '../../../core/widgets/session_controls.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/ayah.dart';
import '../../../data/models/reciter.dart';
import '../../../domain/entities/session_config.dart';
import '../cubit/settings_cubit.dart';
import '../cubit/settings_state.dart';

/// Three groups: عام, القارئ, and the session defaults.
///
/// The session group is an [ExpansionTile] collapsed by default. It holds what
/// used to be a screen of its own, and it is the group a reader touches least
/// — the reader's own drawer is where a session actually gets tuned, and these
/// are only the values it opens with.
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
              _GroupHeading(label: LocaleKeys.settingsSectionGeneral.tr()),
              _ThemeControl(settings: settings, cubit: cubit),
              _HomeViewControl(settings: settings, cubit: cubit),
              _FontSizeControl(
                settings: settings,
                cubit: cubit,
                previewAyah: state.previewAyah,
              ),

              _GroupHeading(label: LocaleKeys.settingsSectionReciter.tr()),
              _ReciterControl(settings: settings, state: state, cubit: cubit),

              _GroupHeading(label: LocaleKeys.settingsSectionStorage.tr()),
              _AudioQualityControl(settings: settings, cubit: cubit),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsetsDirectional.zero,
                title: Text(LocaleKeys.settingsWifiOnly.tr()),
                subtitle: Text(LocaleKeys.settingsWifiOnlyHint.tr()),
                value: settings.downloadOverWifiOnly,
                onChanged: cubit.setDownloadOverWifiOnly,
              ),
              const _SavedRecitationsRow(),

              // No _GroupHeading here: the ExpansionTile's own title is the
              // group's heading. Two widgets carrying the same words read as a
              // heading with an empty section under it.
              _SessionDefaults(settings: settings, cubit: cubit),

              if (state.errorMessage != null)
                Padding(
                  padding: EdgeInsetsDirectional.only(top: 16.h),
                  child: Text(
                    state.errorMessage!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Which bitrate downloads and streams ask for.
///
/// A preference, not a promise: a reciter published at one bitrate is served
/// at that bitrate whatever is chosen here, and nothing already on the device
/// is re-fetched when it changes.
class _AudioQualityControl extends StatelessWidget {
  const _AudioQualityControl({required this.settings, required this.cubit});

  final AppSettings settings;
  final SettingsCubit cubit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SetupSection(
      label: LocaleKeys.settingsAudioQuality.tr(),
      child: RadioGroup<AudioQuality>(
        groupValue: settings.audioQuality,
        onChanged: (AudioQuality? quality) {
          if (quality != null) cubit.setAudioQuality(quality);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final AudioQuality quality in AudioQuality.values)
              RadioListTile<AudioQuality>(
                contentPadding: EdgeInsetsDirectional.zero,
                value: quality,
                title: Text(_label(quality)),
              ),
            Text(
              LocaleKeys.settingsAudioQualityHint.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _label(AudioQuality quality) => switch (quality) {
    AudioQuality.low => LocaleKeys.settingsAudioQualityLow.tr(),
    AudioQuality.standard => LocaleKeys.settingsAudioQualityStandard.tr(),
    AudioQuality.high => LocaleKeys.settingsAudioQualityHigh.tr(),
  };
}

/// The way into the saved-recitations list.
///
/// A row rather than the list itself: what is saved is a handful of surahs at
/// most, and the settings screen is already long.
class _SavedRecitationsRow extends StatelessWidget {
  const _SavedRecitationsRow();

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsetsDirectional.only(bottom: 20.h),
    child: ListTile(
      contentPadding: EdgeInsetsDirectional.zero,
      leading: const Icon(Icons.download_done_outlined),
      title: Text(LocaleKeys.settingsSavedRecitations.tr()),
      subtitle: Text(LocaleKeys.settingsSavedRecitationsHint.tr()),
      // Directional on purpose: the affordance points the way the language
      // reads, so it mirrors with the locale.
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.pushNamed(AppRoutes.downloadsName),
    ),
  );
}

class _GroupHeading extends StatelessWidget {
  const _GroupHeading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: EdgeInsetsDirectional.only(bottom: 12.h, top: 4.h),
      child: Text(
        label,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ThemeControl extends StatelessWidget {
  const _ThemeControl({required this.settings, required this.cubit});

  final AppSettings settings;
  final SettingsCubit cubit;

  @override
  Widget build(BuildContext context) {
    return SetupSection(
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
                title: Text(_label(mode).tr()),
                value: mode,
              ),
          ],
        ),
      ),
    );
  }

  static String _label(AppThemeMode mode) => switch (mode) {
    AppThemeMode.system => LocaleKeys.settingsThemeSystem,
    AppThemeMode.light => LocaleKeys.settingsThemeLight,
    AppThemeMode.dark => LocaleKeys.settingsThemeDark,
  };
}

/// Mirrors the home screen's app-bar toggle. Same stored value, so whichever
/// one the reader touches, the other already agrees.
class _HomeViewControl extends StatelessWidget {
  const _HomeViewControl({required this.settings, required this.cubit});

  final AppSettings settings;
  final SettingsCubit cubit;

  @override
  Widget build(BuildContext context) {
    return SetupSection(
      label: LocaleKeys.settingsHomeViewMode.tr(),
      child: SegmentedButton<HomeViewMode>(
        segments: <ButtonSegment<HomeViewMode>>[
          ButtonSegment<HomeViewMode>(
            value: HomeViewMode.list,
            icon: const Icon(Icons.view_list_outlined),
            label: Text(LocaleKeys.settingsHomeViewList.tr()),
          ),
          ButtonSegment<HomeViewMode>(
            value: HomeViewMode.grid,
            icon: const Icon(Icons.grid_view_outlined),
            label: Text(LocaleKeys.settingsHomeViewGrid.tr()),
          ),
        ],
        selected: <HomeViewMode>{settings.homeViewMode},
        showSelectedIcon: false,
        onSelectionChanged: (Set<HomeViewMode> s) =>
            cubit.setHomeViewMode(s.first),
      ),
    );
  }
}

class _FontSizeControl extends StatelessWidget {
  const _FontSizeControl({
    required this.settings,
    required this.cubit,
    required this.previewAyah,
  });

  final AppSettings settings;
  final SettingsCubit cubit;
  final Ayah? previewAyah;

  @override
  Widget build(BuildContext context) {
    return SetupSection(
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
            valueLabel: settings.arabicFontSize.toLocalisedFixed(0),
            onChanged: (double v) => cubit.setArabicFontSize(v.roundToDouble()),
          ),
          SizedBox(height: 8.h),
          _FontPreview(fontSize: settings.arabicFontSize, ayah: previewAyah),
        ],
      ),
    );
  }
}

class _ReciterControl extends StatelessWidget {
  const _ReciterControl({
    required this.settings,
    required this.state,
    required this.cubit,
  });

  final AppSettings settings;
  final SettingsState state;
  final SettingsCubit cubit;

  @override
  Widget build(BuildContext context) {
    return SetupSection(
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
            // A list even with one entry, so a second reciter needs no UI
            // change (CLAUDE.md A.2 rule 2).
            for (final Reciter reciter in state.reciters)
              RadioListTile<String>(
                contentPadding: EdgeInsetsDirectional.zero,
                secondary: ReciterAvatar(reciter: reciter, diameter: 44),
                title: Text(reciter.nameAr),
                subtitle: Text(reciter.nameEn),
                value: reciter.id,
              ),
          ],
        ),
      ),
    );
  }
}

/// The old session-setup screen's controls, as defaults, collapsed.
class _SessionDefaults extends StatelessWidget {
  const _SessionDefaults({required this.settings, required this.cubit});

  final AppSettings settings;
  final SettingsCubit cubit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ConnectMode mode = settings.defaultConnectMode;
    final bool finalFullPass =
        settings.defaultFinalFullPass ?? mode.defaultFinalFullPass;

    return Theme(
      // The tile sits inside a list of headings; its own dividers would read as
      // a second, competing grouping.
      data: theme.copyWith(dividerColor: AppColors.transparent),
      child: ExpansionTile(
        // Collapsed on first open, every open: these are defaults, and a
        // reader who wants to change a session reaches for the reader's drawer.
        initiallyExpanded: false,
        tilePadding: EdgeInsetsDirectional.zero,
        childrenPadding: EdgeInsetsDirectional.only(bottom: 8.h),
        title: Text(LocaleKeys.settingsSectionSession.tr()),
        subtitle: Text(
          LocaleKeys.settingsSectionSessionHint.tr(),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        children: <Widget>[
          SessionTuningControls(
            repeatCount: settings.defaultRepeatCount,
            connectMode: mode,
            intraBlockPauseMs: settings.defaultIntraBlockPauseMs,
            betweenRepeatPauseMs: settings.defaultBetweenRepeatPauseMs,
            betweenStepsPauseMs: settings.defaultBetweenStepsPauseMs,
            playbackSpeed: settings.defaultPlaybackSpeed,
            onRepeatCount: cubit.setDefaultRepeatCount,
            onConnectMode: cubit.setDefaultConnectMode,
            onIntraBlockPause: cubit.setDefaultIntraBlockPause,
            onBetweenRepeatPause: cubit.setDefaultBetweenRepeatPause,
            onBetweenStepsPause: cubit.setDefaultBetweenStepsPause,
            onPlaybackSpeed: cubit.setDefaultPlaybackSpeed,
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsetsDirectional.zero,
            title: Text(LocaleKeys.sessionSetupFinalFullPass.tr()),
            value: finalFullPass,
            onChanged: cubit.setDefaultFinalFullPass,
          ),
          SizedBox(height: 12.h),
          SetupSection(
            label: LocaleKeys.settingsDefaultRangeBehaviour.tr(),
            child: RadioGroup<RangeBehaviour>(
              groupValue: settings.defaultRangeBehaviour,
              onChanged: (RangeBehaviour? b) {
                if (b != null) cubit.setDefaultRangeBehaviour(b);
              },
              child: Column(
                children: <Widget>[
                  for (final RangeBehaviour behaviour in RangeBehaviour.values)
                    RadioListTile<RangeBehaviour>(
                      contentPadding: EdgeInsetsDirectional.zero,
                      title: Text(_rangeLabel(behaviour).tr()),
                      value: behaviour,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _rangeLabel(RangeBehaviour behaviour) => switch (behaviour) {
    RangeBehaviour.wholeSurah => LocaleKeys.settingsRangeWholeSurah,
    RangeBehaviour.lastUsed => LocaleKeys.settingsRangeLastUsed,
  };
}

/// Shows the chosen size on a real ayah in the real mushaf face — the setting
/// governs scripture, so previewing it with UI text would misrepresent both
/// the size and the letterforms. Rendered through [AyahText] like every other
/// piece of Quranic text in the app.
class _FontPreview extends StatelessWidget {
  const _FontPreview({required this.fontSize, required this.ayah});

  final double fontSize;
  final Ayah? ayah;

  @override
  Widget build(BuildContext context) {
    final Ayah? sample = ayah;
    if (sample == null) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsetsDirectional.all(12.r),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: AyahText(
        text: sample.text,
        fontSize: fontSize,
        textAlign: TextAlign.center,
      ),
    );
  }
}
