import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../core/extensions/number_extensions.dart';
import '../../../core/widgets/ayah_text.dart';
import '../../../data/models/ayah.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/state/load_status.dart';
import '../../../core/widgets/reciter_avatar.dart';
import '../../../core/widgets/session_controls.dart';
import '../../../core/widgets/settings_card.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/reciter.dart';
import '../../../services/app_version_service.dart';
import '../cubit/settings_cubit.dart';
import '../cubit/settings_state.dart';

/// The settings, each group in a container of its own: how the app looks, who
/// recites, audio and storage, the session, and about the app.
///
/// The session's values are a page of their own (`SessionSettingsScreen`),
/// reached from its card: they are the longest group by far, and the one a
/// reader touches least — a session is tuned from the reading view, and these
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
              SettingsCard(
                title: LocaleKeys.settingsCardAppearance.tr(),
                icon: Icons.palette_outlined,
                children: <Widget>[
                  _ThemeControl(settings: settings, cubit: cubit),
                  _HomeViewControl(settings: settings, cubit: cubit),
                  _FontSizeControl(
                    settings: settings,
                    cubit: cubit,
                    previewAyah: state.previewAyah,
                  ),
                ],
              ),
              SettingsCard(
                title: LocaleKeys.settingsSectionReciter.tr(),
                icon: Icons.record_voice_over_outlined,
                children: <Widget>[
                  _ReciterControl(
                    settings: settings,
                    state: state,
                    cubit: cubit,
                  ),
                ],
              ),
              SettingsCard(
                title: LocaleKeys.settingsCardAudio.tr(),
                icon: Icons.headphones_outlined,
                children: <Widget>[
                  _AudioQualityControl(settings: settings, cubit: cubit),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsetsDirectional.zero,
                    title: Text(LocaleKeys.settingsWifiOnly.tr()),
                    subtitle: Text(LocaleKeys.settingsWifiOnlyHint.tr()),
                    value: settings.downloadOverWifiOnly,
                    onChanged: cubit.setDownloadOverWifiOnly,
                  ),
                  SettingsLinkRow(
                    icon: Icons.download_done_outlined,
                    title: LocaleKeys.settingsSavedRecitations.tr(),
                    subtitle: LocaleKeys.settingsSavedRecitationsHint.tr(),
                    onTap: () => context.pushNamed(AppRoutes.downloadsName),
                  ),
                ],
              ),
              SettingsCard(
                title: LocaleKeys.settingsCardSession.tr(),
                icon: Icons.repeat,
                children: <Widget>[
                  SettingsLinkRow(
                    icon: Icons.tune,
                    title: LocaleKeys.settingsSectionSession.tr(),
                    subtitle: LocaleKeys.settingsSectionSessionHint.tr(),
                    onTap: () =>
                        context.pushNamed(AppRoutes.sessionSettingsName),
                  ),
                ],
              ),
              SettingsCard(
                title: LocaleKeys.settingsCardAbout.tr(),
                icon: Icons.info_outline,
                children: <Widget>[
                  SettingsLinkRow(
                    icon: Icons.menu_book_outlined,
                    title: LocaleKeys.aboutHowToUse.tr(),
                    onTap: () => context.pushNamed(AppRoutes.howToUseName),
                  ),
                  SettingsLinkRow(
                    icon: Icons.flag_outlined,
                    title: LocaleKeys.aboutGoal.tr(),
                    onTap: () => context.pushNamed(AppRoutes.goalName),
                  ),
                  SettingsLinkRow(
                    icon: Icons.groups_outlined,
                    title: LocaleKeys.aboutUs.tr(),
                    onTap: () => context.pushNamed(AppRoutes.aboutUsName),
                  ),
                  SettingsLinkRow(
                    icon: Icons.person_outline,
                    title: LocaleKeys.aboutDeveloper.tr(),
                    onTap: () => context.pushNamed(AppRoutes.developerName),
                  ),
                ],
              ),

              if (state.appVersion case final InstalledVersion v)
                Padding(
                  padding: EdgeInsetsDirectional.only(top: 4.h, bottom: 12.h),
                  child: Text(
                    LocaleKeys.settingsVersion.tr(
                      args: <String>[v.version, v.buildNumber],
                    ),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),

              if (state.errorMessage != null)
                Padding(
                  padding: EdgeInsetsDirectional.only(top: 4.h),
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

/// How the home page is drawn — and, for the mushaf, how the app opens.
class _HomeViewControl extends StatelessWidget {
  const _HomeViewControl({required this.settings, required this.cubit});

  final AppSettings settings;
  final SettingsCubit cubit;

  @override
  Widget build(BuildContext context) {
    return SetupSection(
      label: LocaleKeys.settingsHomeViewMode.tr(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SegmentedButton<HomeViewMode>(
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
              ButtonSegment<HomeViewMode>(
                value: HomeViewMode.mushaf,
                icon: const Icon(Icons.auto_stories_outlined),
                label: Text(LocaleKeys.settingsHomeViewMushaf.tr()),
              ),
            ],
            selected: <HomeViewMode>{settings.homeViewMode},
            showSelectedIcon: false,
            onSelectionChanged: (Set<HomeViewMode> s) =>
                cubit.setHomeViewMode(s.first),
          ),
          // Said only when it applies: this option changes how the app
          // *opens*, which a segmented button alone does not convey.
          if (settings.homeViewMode == HomeViewMode.mushaf)
            Padding(
              padding: EdgeInsetsDirectional.only(top: 8.h),
              child: Text(
                LocaleKeys.settingsHomeViewMushafHint.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
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
          SizedBox(height: 8.h),
          // What the slider does to a page is not obvious from a sample line,
          // so it is said: past the middle, the page is no longer the printed
          // page line for line.
          Text(
            LocaleKeys.settingsArabicFontSizeHint.tr(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
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
    // No label of its own: the card it sits in is already headed «القارئ».
    return Padding(
      padding: EdgeInsetsDirectional.only(bottom: 8.h),
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
                subtitle: Text(
                  reciter.attribution.isEmpty
                      ? reciter.nameEn
                      : '${reciter.nameEn}\n'
                            '${reciter.attribution.of(context.locale.languageCode)}',
                ),
                value: reciter.id,
              ),
          ],
        ),
      ),
    );
  }
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
