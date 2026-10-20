import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../core/desktop.dart';
import '../../../core/localization/app_localization.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/state/load_status.dart';
import '../../../core/widgets/memorization_view_control.dart';
import '../../../core/widgets/reciter_dropdown.dart';
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

          return DesktopWidth(
            child: ListView(
              padding: EdgeInsetsDirectional.all(16.r),
              children: <Widget>[
                SettingsCard(
                  title: LocaleKeys.settingsCardAppearance.tr(),
                  icon: Icons.palette_outlined,
                  children: <Widget>[
                    _ThemeControl(settings: settings, cubit: cubit),
                    const _LanguageControl(),
                    _HomeViewControl(settings: settings, cubit: cubit),
                    _PageTurnControl(settings: settings, cubit: cubit),
                    SettingsLinkRow(
                      icon: Icons.text_fields,
                      title: LocaleKeys.mushafFontTitle.tr(),
                      subtitle: LocaleKeys.mushafFontHint.tr(),
                      onTap: () => context.pushNamed(AppRoutes.mushafFontName),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsetsDirectional.zero,
                      secondary: const Icon(Icons.bookmark_outline),
                      title: Text(LocaleKeys.settingsReadingRibbon.tr()),
                      subtitle: Text(LocaleKeys.settingsReadingRibbonHint.tr()),
                      value: settings.showReadingRibbon,
                      onChanged: cubit.setShowReadingRibbon,
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsetsDirectional.zero,
                      secondary: const Icon(Icons.flag_outlined),
                      title: Text(LocaleKeys.settingsShowStumbles.tr()),
                      subtitle: Text(LocaleKeys.settingsShowStumblesHint.tr()),
                      value: settings.showStumbles,
                      onChanged: cubit.setShowStumbles,
                    ),
                    MemorizationViewControl(
                      value: settings.memorizationView,
                      onChanged: cubit.setMemorizationView,
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
                    SettingsLinkRow(
                      icon: Icons.download_for_offline_outlined,
                      title: LocaleKeys.settingsWholeMushaf.tr(),
                      subtitle: LocaleKeys.settingsWholeMushafHint.tr(),
                      onTap: () =>
                          context.pushNamed(AppRoutes.mushafDownloadName),
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
                    SettingsLinkRow(
                      icon: Icons.flag_outlined,
                      title: LocaleKeys.weakSpotsTitle.tr(),
                      subtitle: LocaleKeys.weakSpotsHint.tr(),
                      onTap: () => context.pushNamed(AppRoutes.weakSpotsName),
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
                      icon: Icons.lightbulb_outline,
                      title: LocaleKeys.aboutIdea.tr(),
                      onTap: () => context.pushNamed(AppRoutes.ideaName),
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
            ),
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

/// The interface language. Kept by easy_localization itself, not in the
/// settings map: it is read before anything else is, on the splash. The
/// mushaf's own direction does not change with it (CLAUDE.md A.2 rule 4).
class _LanguageControl extends StatelessWidget {
  const _LanguageControl();

  @override
  Widget build(BuildContext context) {
    return SetupSection(
      label: LocaleKeys.settingsLanguage.tr(),
      child: RadioGroup<Locale>(
        groupValue: context.locale,
        onChanged: (Locale? locale) {
          if (locale != null) context.setLocale(locale);
        },
        child: Column(
          children: <Widget>[
            for (final Locale locale in AppLocalization.supportedLocales)
              RadioListTile<Locale>(
                contentPadding: EdgeInsetsDirectional.zero,
                // Each language named in itself, so that whoever cannot read
                // the current one can still find their own.
                title: Text(
                  locale == AppLocalization.arabic
                      ? LocaleKeys.settingsLanguageAr.tr()
                      : LocaleKeys.settingsLanguageEn.tr(),
                ),
                value: locale,
              ),
          ],
        ),
      ),
    );
  }
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

/// How the mushaf's pages turn: folding over like paper, or the plain slide.
class _PageTurnControl extends StatelessWidget {
  const _PageTurnControl({required this.settings, required this.cubit});

  final AppSettings settings;
  final SettingsCubit cubit;

  @override
  Widget build(BuildContext context) {
    return SetupSection(
      label: LocaleKeys.settingsPageTurn.tr(),
      child: SegmentedButton<PageTurnStyle>(
        segments: <ButtonSegment<PageTurnStyle>>[
          ButtonSegment<PageTurnStyle>(
            value: PageTurnStyle.paper,
            icon: const Icon(Icons.menu_book_outlined),
            label: Text(LocaleKeys.settingsPageTurnPaper.tr()),
          ),
          ButtonSegment<PageTurnStyle>(
            value: PageTurnStyle.slide,
            icon: const Icon(Icons.swap_horiz),
            label: Text(LocaleKeys.settingsPageTurnNormal.tr()),
          ),
        ],
        selected: <PageTurnStyle>{settings.pageTurnStyle},
        showSelectedIcon: false,
        onSelectionChanged: (Set<PageTurnStyle> s) =>
            cubit.setPageTurnStyle(s.first),
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
    // The same field as the session sheet's, so a reciter is picked the same
    // way everywhere (CLAUDE.md A.2 rule 2: a list of data, never of code).
    return Padding(
      padding: EdgeInsetsDirectional.only(bottom: 8.h),
      child: ReciterDropdown(
        reciters: state.reciters,
        currentId:
            settings.reciterId ??
            (state.reciters.isEmpty ? null : state.reciters.first.id),
        onChanged: (Reciter picked) => cubit.setReciter(picked.id),
      ),
    );
  }
}
