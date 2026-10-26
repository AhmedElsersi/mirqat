import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../core/desktop.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/app_localization.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/state/load_status.dart';
import '../../../core/theme/quran_font.dart';
import '../../../core/widgets/panel.dart';
import '../../../core/widgets/reciter_avatar.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/reciter.dart';
import '../../../domain/entities/session_config.dart';
import '../../../services/app_version_service.dart';
import '../cubit/settings_cubit.dart';
import '../cubit/settings_state.dart';

/// The settings, and only the settings — the hifz tools live under My hifz.
/// Four groups under their own labels: how the app looks, who recites and
/// what is on the device, what a session starts from, and what the app says
/// about itself.
///
/// The theme, the one choice with three short answers, is a segmented
/// control; everything else is a row of a list that says where it stands now
/// in one line, and opens onto the rest. Nothing is a column of radio rows or
/// a paragraph, which is what this screen used to be.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // A tab of the home, where it has a title of its own like the others;
    // pushed from the session sheet, with the way back beside it.
    final bool pushed = ModalRoute.of(context)?.canPop ?? false;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: BlocBuilder<SettingsCubit, SettingsState>(
          builder: (BuildContext context, SettingsState state) {
            if (state.status.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            final SettingsCubit cubit = context.read<SettingsCubit>();
            final AppSettings settings = state.settings;
            final bool arabic = context.locale.languageCode == 'ar';

            return DesktopWidth(
              child: ListView(
                padding: EdgeInsetsDirectional.fromSTEB(16.w, 6.h, 16.w, 24.h),
                children: <Widget>[
                  Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(
                      pushed ? 0 : 4.w,
                      0,
                      4.w,
                      6.h,
                    ),
                    child: Row(
                      children: <Widget>[
                        if (pushed) const BackButton(),
                        Expanded(
                          child: Text(
                            LocaleKeys.settingsTitle.tr(),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  FieldLabel(LocaleKeys.settingsTheme.tr()),
                  _ThemeControl(settings: settings, cubit: cubit),
                  SizedBox(height: 12.h),
                  _ListCard(
                    children: <Widget>[
                      _Row(
                        icon: Icons.text_fields,
                        title: LocaleKeys.mushafFontTitle.tr(),
                        subtitle: joinDetails(<String>[
                          _fontLabel(settings.quranFont).tr(),
                          settings.arabicFontSize.toLocalisedFixed(0),
                        ]),
                        onTap: () =>
                            context.pushNamed(AppRoutes.mushafFontName),
                      ),
                      _Row(
                        icon: Icons.visibility_off_outlined,
                        title: LocaleKeys.memorizationViewTitle.tr(),
                        subtitle: _viewLabel(settings.memorizationView).tr(),
                        onTap: () => _pickMemorizationView(
                          context,
                          settings.memorizationView,
                          cubit.setMemorizationView,
                        ),
                      ),
                      _SwitchRow(
                        icon: Icons.bookmark_outline,
                        title: LocaleKeys.settingsReadingRibbon.tr(),
                        value: settings.showReadingRibbon,
                        onChanged: cubit.setShowReadingRibbon,
                      ),
                      _SwitchRow(
                        icon: Icons.flag_outlined,
                        title: LocaleKeys.settingsShowStumbles.tr(),
                        value: settings.showStumbles,
                        onChanged: cubit.setShowStumbles,
                      ),
                      _Row(
                        icon: Icons.chrome_reader_mode_outlined,
                        title: LocaleKeys.settingsFirstScreen.tr(),
                        subtitle:
                            (settings.homeViewMode == HomeViewMode.mushaf
                                    ? LocaleKeys.settingsOpensLastPage
                                    : LocaleKeys.settingsOpensToday)
                                .tr(),
                        onTap: () => _pickFirstScreen(context),
                      ),
                      _Row(
                        icon: Icons.auto_stories_outlined,
                        title: LocaleKeys.settingsPageTurn.tr(),
                        subtitle: _turnLabel(settings.pageTurnStyle).tr(),
                        onTap: () => _pickOne<PageTurnStyle>(
                          context,
                          title: LocaleKeys.settingsPageTurn.tr(),
                          values: PageTurnStyle.values,
                          current: settings.pageTurnStyle,
                          label: (PageTurnStyle s) => _turnLabel(s).tr(),
                          onChanged: cubit.setPageTurnStyle,
                        ),
                      ),
                    ],
                  ),

                  FieldLabel(LocaleKeys.readerReciterAndAudio.tr()),
                  _ListCard(
                    children: <Widget>[
                      // The reciter as a row of the list: their portrait,
                      // their name, the quality they are fetched at; a tap
                      // offers everyone, and the quality, as a sheet.
                      _ReciterRow(
                        reciters: state.reciters,
                        currentId:
                            settings.reciterId ??
                            (state.reciters.isEmpty
                                ? null
                                : state.reciters.first.id),
                        quality: settings.audioQuality,
                        arabic: arabic,
                        onChanged: (Reciter picked) =>
                            cubit.setReciter(picked.id),
                      ),
                      _Row(
                        icon: Icons.download_outlined,
                        title: LocaleKeys.settingsDownloads.tr(),
                        subtitle: LocaleKeys.settingsDownloadsHint.tr(),
                        onTap: () => _openDownloads(context),
                      ),
                      _SwitchRow(
                        icon: Icons.wifi,
                        title: LocaleKeys.settingsWifiOnly.tr(),
                        value: settings.downloadOverWifiOnly,
                        onChanged: cubit.setDownloadOverWifiOnly,
                      ),
                    ],
                  ),

                  FieldLabel(LocaleKeys.settingsCardSession.tr()),
                  _ListCard(
                    children: <Widget>[
                      _Row(
                        icon: Icons.tune,
                        title: LocaleKeys.settingsSectionSession.tr(),
                        // What a session will open with, said here rather
                        // than only on the page it is set from.
                        subtitle: _sessionSummary(settings),
                        onTap: () =>
                            context.pushNamed(AppRoutes.sessionSettingsName),
                      ),
                      // RELEASE-1.4(bookends)
                      // _SwitchRow(
                      //   icon: Icons.bedtime_outlined,
                      //   title: LocaleKeys.reviewBookendsTitle.tr(),
                      //   subtitle: LocaleKeys.reviewBookendsHint.tr(),
                      //   value: settings.bookends,
                      //   onChanged: cubit.setBookends,
                      // ),
                      // END RELEASE-1.4(bookends)
                    ],
                  ),

                  FieldLabel(LocaleKeys.settingsCardAbout.tr()),
                  _ListCard(
                    children: <Widget>[
                      _Row(
                        icon: Icons.help_outline,
                        title: LocaleKeys.aboutHowToUse.tr(),
                        onTap: () => context.pushNamed(AppRoutes.howToUseName),
                      ),
                      const _LanguageRow(),
                      _Row(
                        icon: Icons.info_outline,
                        title: LocaleKeys.aboutAboutApp.tr(
                          args: <String>[LocaleKeys.appName.tr()],
                        ),
                        onTap: () => context.pushNamed(AppRoutes.aboutName),
                      ),
                    ],
                  ),

                  if (state.appVersion case final InstalledVersion v)
                    Padding(
                      padding: EdgeInsetsDirectional.only(top: 18.h),
                      child: Text(
                        LocaleKeys.settingsVersion.tr(
                          args: <String>[v.version, v.buildNumber],
                        ),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),

                  if (state.errorMessage != null)
                    Padding(
                      padding: EdgeInsetsDirectional.only(top: 8.h),
                      child: Text(
                        state.errorMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// «تراكمي، ٣ تكرار، جولة استرجاع» — what the next session opens with.
  static String _sessionSummary(AppSettings settings) => joinDetails(<String>[
    switch (settings.defaultConnectMode) {
      ConnectMode.cumulative => LocaleKeys.sessionSetupConnectCumulative,
      ConnectMode.continuous => LocaleKeys.sessionSetupConnectContinuous,
      ConnectMode.none => LocaleKeys.sessionSetupConnectNone,
    }.tr(),
    LocaleKeys.progressRepeats.tr(
      args: <String>[settings.defaultRepeatCount.toLocalisedString()],
    ),
    if (settings.defaultRecallRounds > 0)
      LocaleKeys.sessionSetupRecallRounds.tr(),
  ]);

  static String _fontLabel(QuranFont font) => switch (font) {
    QuranFont.hafsV22 => LocaleKeys.mushafFontHafsV22,
    QuranFont.hafsV18 => LocaleKeys.mushafFontHafsV18,
    QuranFont.qpcV2 => LocaleKeys.mushafFontQpcV2,
  };

  static String _viewLabel(MemorizationView view) => switch (view) {
    MemorizationView.off => LocaleKeys.memorizationViewOff,
    MemorizationView.firstWords => LocaleKeys.memorizationViewFirstWords,
    MemorizationView.markersOnly => LocaleKeys.memorizationViewMarkersOnly,
  };

  static String _turnLabel(PageTurnStyle style) => switch (style) {
    PageTurnStyle.paper => LocaleKeys.settingsPageTurnPaper,
    PageTurnStyle.slide => LocaleKeys.settingsPageTurnNormal,
  };

  static Future<void> _pickMemorizationView(
    BuildContext context,
    MemorizationView current,
    ValueChanged<MemorizationView> onChanged,
  ) => _pickOne<MemorizationView>(
    context,
    title: LocaleKeys.memorizationViewTitle.tr(),
    hint: LocaleKeys.memorizationViewHint.tr(),
    values: MemorizationView.values,
    current: current,
    label: (MemorizationView v) => _viewLabel(v).tr(),
    onChanged: onChanged,
  );

  /// What the app opens on: Today, or the last page read. Today leaves the
  /// mushaf one tab away, and its index drawn as a list or a grid.
  static Future<void> _pickFirstScreen(
    BuildContext context,
  ) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext sheet) => BlocBuilder<SettingsCubit, SettingsState>(
      builder: (BuildContext context, SettingsState state) {
        final ThemeData theme = Theme.of(context);
        final SettingsCubit cubit = context.read<SettingsCubit>();
        final HomeViewMode mode = state.settings.homeViewMode;
        final bool lastPage = mode == HomeViewMode.mushaf;
        return SafeArea(
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(16.w, 0, 16.w, 16.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  LocaleKeys.settingsFirstScreen.tr(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 12.h),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: <ButtonSegment<bool>>[
                    ButtonSegment<bool>(
                      value: false,
                      label: Text(LocaleKeys.tabsToday.tr()),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      label: Text(LocaleKeys.settingsHomeViewMushaf.tr()),
                    ),
                  ],
                  selected: <bool>{lastPage},
                  onSelectionChanged: (Set<bool> s) => cubit.setHomeViewMode(
                    s.single ? HomeViewMode.mushaf : HomeViewMode.list,
                  ),
                ),
                Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(4.w, 8.h, 4.w, 0),
                  child: Text(
                    (lastPage
                            ? LocaleKeys.settingsOpensLastPage
                            : LocaleKeys.settingsOpensToday)
                        .tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                // The index's own shape, which only the Mushaf tab
                // shows: the last page has the plain list behind it.
                if (!lastPage) ...<Widget>[
                  FieldLabel(LocaleKeys.settingsHomeViewMode.tr()),
                  SegmentedButton<HomeViewMode>(
                    showSelectedIcon: false,
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
                    selected: <HomeViewMode>{mode},
                    onSelectionChanged: (Set<HomeViewMode> s) =>
                        cubit.setHomeViewMode(s.single),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );

  /// Everything that is kept on the device, one tap from one row: the saved
  /// recitations, the whole mushaf for one reciter, and the page fonts.
  static Future<void> _openDownloads(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (BuildContext sheet) {
          // The sheet gives way and the screen opens in the same tap.
          void open(String route) {
            Navigator.of(sheet).pop();
            context.pushNamed(route);
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(16.w, 0, 16.w, 16.h),
              child: _ListCard(
                children: <Widget>[
                  _Row(
                    icon: Icons.download_done_outlined,
                    title: LocaleKeys.settingsSavedRecitations.tr(),
                    subtitle: LocaleKeys.settingsSavedRecitationsHint.tr(),
                    onTap: () => open(AppRoutes.downloadsName),
                  ),
                  _Row(
                    icon: Icons.download_for_offline_outlined,
                    title: LocaleKeys.settingsWholeMushaf.tr(),
                    subtitle: LocaleKeys.settingsWholeMushafHint.tr(),
                    onTap: () => open(AppRoutes.mushafDownloadName),
                  ),
                  _Row(
                    icon: Icons.font_download_outlined,
                    title: LocaleKeys.mushafFontQpcFontsTitle.tr(),
                    subtitle: LocaleKeys.mushafFontQpcV2.tr(),
                    onTap: () => open(AppRoutes.mushafFontName),
                  ),
                ],
              ),
            ),
          );
        },
      );
}

/// One choice of several, as a sheet: the options and, where they need it,
/// the line that explains them — instead of a column of radio rows kept open
/// on the page for a setting that is touched once.
Future<void> _pickOne<T extends Object>(
  BuildContext context, {
  required String title,
  required List<T> values,
  required T current,
  required String Function(T) label,
  required ValueChanged<T> onChanged,
  String? hint,
}) async {
  final T? picked = await showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext sheet) {
      final ThemeData theme = Theme.of(sheet);
      return SafeArea(
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(16.w, 0, 16.w, 16.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 8.h),
              RadioGroup<T>(
                groupValue: current,
                onChanged: (T? value) =>
                    Navigator.of(sheet).pop(value ?? current),
                child: Column(
                  children: <Widget>[
                    for (final T value in values)
                      RadioListTile<T>(
                        contentPadding: EdgeInsetsDirectional.zero,
                        value: value,
                        title: Text(label(value)),
                      ),
                  ],
                ),
              ),
              if (hint != null) ...<Widget>[
                SizedBox(height: 4.h),
                Text(
                  hint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
  if (picked != null && picked != current) onChanged(picked);
}

/// A `.list`: rows on one card, a hairline between each.
class _ListCard extends StatelessWidget {
  const _ListCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: EdgeInsetsDirectional.zero,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < children.length; i++) ...<Widget>[
          if (i > 0) const Divider(height: 1),
          children[i],
        ],
      ],
    ),
  );
}

/// A row that says where a setting stands, in one line, and opens onto the
/// rest of it.
class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      leading: TileIcon(icon),
      title: Text(title, style: theme.textTheme.titleSmall),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      trailing:
          trailing ??
          Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
    );
  }
}

/// A setting that is on or off: its name, and the switch.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    // RELEASE-1.4(bookends): the bookends row is the one that sets this.
    // ignore: unused_element_parameter
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SwitchListTile.adaptive(
      secondary: TileIcon(icon),
      title: Text(title, style: theme.textTheme.titleSmall),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      value: value,
      onChanged: onChanged,
    );
  }
}

/// The interface language. Kept by easy_localization itself, not in the
/// settings map: it is read before anything else is, on the splash. The
/// mushaf's own direction does not change with it (CLAUDE.md A.2 rule 4).
class _LanguageRow extends StatelessWidget {
  const _LanguageRow();

  static String _name(Locale locale) => locale == AppLocalization.arabic
      ? LocaleKeys.settingsLanguageAr.tr()
      : LocaleKeys.settingsLanguageEn.tr();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return _Row(
      icon: Icons.translate,
      title: LocaleKeys.settingsLanguage.tr(),
      // The value alone: what it is set to says it can be set.
      trailing: Text(
        _name(context.locale),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: () async {
        final Locale? picked = await showModalBottomSheet<Locale>(
          context: context,
          showDragHandle: true,
          builder: (BuildContext sheet) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final Locale locale in AppLocalization.supportedLocales)
                  ListTile(
                    selected: locale == context.locale,
                    // Each language named in itself, so that whoever cannot
                    // read the current one can still find their own.
                    title: Text(_name(locale)),
                    trailing: locale == context.locale
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => Navigator.of(sheet).pop(locale),
                  ),
              ],
            ),
          ),
        );
        if (picked != null && context.mounted) await context.setLocale(picked);
      },
    );
  }
}

/// Light, as the phone does, or dark.
class _ThemeControl extends StatelessWidget {
  const _ThemeControl({required this.settings, required this.cubit});

  final AppSettings settings;
  final SettingsCubit cubit;

  @override
  Widget build(BuildContext context) {
    // Three short choices, side by side: one row, not three.
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<AppThemeMode>(
        showSelectedIcon: false,
        segments: <ButtonSegment<AppThemeMode>>[
          for (final AppThemeMode mode in <AppThemeMode>[
            AppThemeMode.light,
            AppThemeMode.system,
            AppThemeMode.dark,
          ])
            ButtonSegment<AppThemeMode>(
              value: mode,
              label: Text(
                _label(mode).tr(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        selected: <AppThemeMode>{settings.themeMode},
        onSelectionChanged: (Set<AppThemeMode> chosen) =>
            cubit.setThemeMode(chosen.single),
      ),
    );
  }

  static String _label(AppThemeMode mode) => switch (mode) {
    AppThemeMode.system => LocaleKeys.settingsThemeSystem,
    AppThemeMode.light => LocaleKeys.settingsThemeLight,
    AppThemeMode.dark => LocaleKeys.settingsThemeDark,
  };
}

/// The reciter, as a row: the portrait, the name, and under it the quality
/// their recitation is fetched at and the attribution where there is one. A
/// tap opens everyone as a sheet, with the quality under them.
class _ReciterRow extends StatelessWidget {
  const _ReciterRow({
    required this.reciters,
    required this.currentId,
    required this.quality,
    required this.arabic,
    required this.onChanged,
  });

  final List<Reciter> reciters;
  final String? currentId;
  final AudioQuality quality;
  final bool arabic;
  final ValueChanged<Reciter> onChanged;

  static String _kbps(AudioQuality q) => LocaleKeys.downloadsBitrate.tr(
    args: <String>[q.bitrate.toLocalisedString()],
  );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Reciter? current = reciters
        .where((Reciter r) => r.id == currentId)
        .firstOrNull;
    final String attribution =
        current?.attribution.of(context.locale.languageCode) ?? '';
    return ListTile(
      onTap: () => _pick(context),
      leading: current == null
          ? const TileIcon(Icons.record_voice_over_outlined)
          : ReciterAvatar(reciter: current, diameter: 40),
      title: Text(
        current == null
            ? LocaleKeys.settingsReciter.tr()
            : (arabic ? current.nameAr : current.nameEn),
        style: theme.textTheme.titleSmall,
      ),
      subtitle: Text(
        joinDetails(<String>[
          _kbps(quality),
          if (attribution.isNotEmpty) attribution,
        ]),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final Reciter? picked = await showModalBottomSheet<Reciter>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheet) {
        final ThemeData theme = Theme.of(sheet);
        final String language = context.locale.languageCode;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: 0.8.sh),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(16.w, 0, 16.w, 8.h),
                  child: Text(
                    LocaleKeys.settingsReciter.tr(),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: <Widget>[
                      for (final Reciter r in reciters)
                        ListTile(
                          selected: r.id == currentId,
                          leading: ReciterAvatar(reciter: r, diameter: 40),
                          title: Text(arabic ? r.nameAr : r.nameEn),
                          subtitle: r.attribution.of(language).isEmpty
                              ? null
                              : Text(r.attribution.of(language)),
                          trailing: r.id == currentId
                              ? const Icon(Icons.check)
                              : null,
                          onTap: () => Navigator.of(sheet).pop(r),
                        ),
                    ],
                  ),
                ),
                // Which bitrate downloads and streams ask for. A preference,
                // not a promise: a reciter published at one bitrate is served
                // at it whatever is chosen, and nothing on the device is
                // fetched again — which the line under it says.
                Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(16.w, 0, 16.w, 16.h),
                  child: BlocBuilder<SettingsCubit, SettingsState>(
                    builder: (BuildContext context, SettingsState state) =>
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            FieldLabel(LocaleKeys.settingsAudioQuality.tr()),
                            SegmentedButton<AudioQuality>(
                              showSelectedIcon: false,
                              segments: <ButtonSegment<AudioQuality>>[
                                for (final AudioQuality q
                                    in AudioQuality.values)
                                  ButtonSegment<AudioQuality>(
                                    value: q,
                                    label: Text(
                                      _kbps(q),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              selected: <AudioQuality>{
                                state.settings.audioQuality,
                              },
                              onSelectionChanged: (Set<AudioQuality> s) =>
                                  context.read<SettingsCubit>().setAudioQuality(
                                    s.single,
                                  ),
                            ),
                            Padding(
                              padding: EdgeInsetsDirectional.fromSTEB(
                                4.w,
                                8.h,
                                4.w,
                                0,
                              ),
                              child: Text(
                                LocaleKeys.settingsAudioQualityHint.tr(),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null && picked.id != currentId) onChanged(picked);
  }
}
