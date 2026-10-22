import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/desktop.dart';
import '../../../core/di/injection.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/theme/quran_font.dart';
import '../../../core/widgets/ayah_text.dart';
import '../../../core/widgets/islamic_frame.dart';
import '../../../core/widgets/panel.dart';
import '../../../core/widgets/session_controls.dart';
import '../../../core/widgets/settings_card.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/ayah.dart';
import '../../../services/qpc_font_service.dart';
import '../cubit/settings_cubit.dart';
import '../cubit/settings_state.dart';
import 'downloads_screen.dart' show megabytes;

/// The mushaf's face and its size, with a real ayah drawn the way the pages
/// will draw it — chosen here, on a page of its own, rather than guessed at
/// from a label.
///
/// The sample is scripture from `quran.db`, through [AyahText] like every
/// other ayah (CLAUDE.md A.2 rule 1); only the face and the size change.
class MushafFontScreen extends StatelessWidget {
  const MushafFontScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(LocaleKeys.mushafFontTitle.tr())),
      body: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (BuildContext context, SettingsState state) {
          final SettingsCubit cubit = context.read<SettingsCubit>();
          final AppSettings settings = state.settings;
          final Ayah? sample = state.previewAyah;

          return DesktopWidth(
            child: ListView(
              padding: EdgeInsetsDirectional.all(16.r),
              children: <Widget>[
                _Preview(
                  ayah: sample,
                  font: settings.quranFont,
                  fontSize: settings.arabicFontSize,
                ),
                SizedBox(height: 16.h),
                SettingsCard(
                  title: LocaleKeys.mushafFontFace.tr(),
                  icon: Icons.font_download_outlined,
                  children: <Widget>[
                    RadioGroup<QuranFont>(
                      groupValue: settings.quranFont,
                      onChanged: (QuranFont? f) {
                        if (f != null) cubit.setQuranFont(f);
                      },
                      child: Column(
                        children: <Widget>[
                          for (final QuranFont font in QuranFont.values)
                            _FontOption(font: font, sample: sample),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsetsDirectional.only(top: 4.h),
                      child: Text(
                        LocaleKeys.mushafFontOnlyMatching.tr(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                SettingsCard(
                  title: LocaleKeys.settingsArabicFontSize.tr(),
                  icon: Icons.format_size,
                  children: <Widget>[
                    LabelledSlider(
                      label: LocaleKeys.settingsArabicFontSize.tr(),
                      value: settings.arabicFontSize,
                      min: AppSettings.minArabicFontSize,
                      max: AppSettings.maxArabicFontSize,
                      divisions: 11,
                      valueLabel: settings.arabicFontSize.toLocalisedFixed(0),
                      onChanged: (double v) =>
                          cubit.setArabicFontSize(v.roundToDouble()),
                    ),
                    // Where the printed page is reproduced line for line.
                    // Said as a way back to it, not as a mark on the track:
                    // a reader who has gone past it wants it back in a tap.
                    if (settings.arabicFontSize !=
                        AppSettings.defaultArabicFontSize)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          onPressed: () => cubit.setArabicFontSize(
                            AppSettings.defaultArabicFontSize,
                          ),
                          child: Text(
                            LocaleKeys.mushafFontDefaultSize.tr(
                              args: <String>[
                                AppSettings.defaultArabicFontSize
                                    .toLocalisedFixed(0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    // What the slider does to a page is not obvious from a
                    // sample, so it is said: past the middle, the page is no
                    // longer the printed page line for line.
                    Text(
                      LocaleKeys.settingsArabicFontSizeHint.tr(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (settings.quranFont.pageFonts)
                  SettingsCard(
                    title: LocaleKeys.mushafFontQpcFontsTitle.tr(),
                    icon: Icons.download_outlined,
                    children: const <Widget>[_QpcFonts()],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The sample ayah in the illuminated frame, in the chosen face at the chosen
/// size: a corner of a page as it will look.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.ayah,
    required this.font,
    required this.fontSize,
  });

  final Ayah? ayah;
  final QuranFont font;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final Ayah? sample = ayah;
    return IslamicFrame(
      labels: FrameLabels(bottom: LocaleKeys.mushafFontPreview.tr()),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: EdgeInsetsDirectional.symmetric(
            horizontal: 8.w,
            vertical: 16.h,
          ),
          child: sample == null
              ? const Center(child: CircularProgressIndicator())
              // Its own scope, so the preview answers the choice the moment
              // it is made, not once the setting has gone round the app.
              : QuranFontScope(
                  font: font,
                  child: AyahText(
                    text: sample.text,
                    fontSize: fontSize,
                    textAlign: TextAlign.center,
                  ),
                ),
        ),
      ),
    );
  }
}

/// One face, named, with the sample drawn small in that face so the choices
/// can be told apart before one is picked.
class _FontOption extends StatelessWidget {
  const _FontOption({required this.font, required this.sample});

  final QuranFont font;
  final Ayah? sample;

  @override
  Widget build(BuildContext context) {
    final Ayah? ayah = sample;
    return RadioListTile<QuranFont>(
      contentPadding: EdgeInsetsDirectional.zero,
      value: font,
      title: Text(_nameKey(font).tr()),
      // Its pages are drawn in fonts fetched page by page: said in words, not
      // shown in a face the sample would only borrow.
      subtitle: font.pageFonts
          ? Text(
              LocaleKeys.mushafFontQpcV2Hint.tr(),
              style: Theme.of(context).textTheme.bodySmall,
            )
          : ayah == null
          ? null
          : QuranFontScope(
              font: font,
              child: AyahText(
                text: ayah.text,
                fontSize: 16,
                textAlign: TextAlign.start,
              ),
            ),
    );
  }

  static String _nameKey(QuranFont font) => switch (font) {
    QuranFont.hafsV22 => LocaleKeys.mushafFontHafsV22,
    QuranFont.hafsV18 => LocaleKeys.mushafFontHafsV18,
    QuranFont.qpcV2 => LocaleKeys.mushafFontQpcV2,
  };
}

/// The QPC V2 page fonts on this device: how many, every one fetched at
/// once for reading offline, or all of them removed.
class _QpcFonts extends StatefulWidget {
  const _QpcFonts();

  @override
  State<_QpcFonts> createState() => _QpcFontsState();
}

class _QpcFontsState extends State<_QpcFonts> {
  final QpcFontService _fonts = sl<QpcFontService>();
  int? _onDevice;
  ({int pages, int bytes})? _totals;
  (int, int)? _progress;
  bool _stop = false;
  int _failed = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final int count = await _fonts.downloadedCount();
    final ({int pages, int bytes}) totals = await _fonts.totals();
    if (!mounted) return;
    setState(() {
      _onDevice = count;
      _totals = totals;
    });
  }

  Future<void> _downloadAll() async {
    setState(() {
      _stop = false;
      _failed = 0;
      _progress = (0, _totals?.pages ?? 0);
    });
    final int failed = await _fonts.downloadAll(
      onProgress: (int done, int total) {
        if (mounted) setState(() => _progress = (done, total));
      },
      cancelled: () => _stop || !mounted,
    );
    if (!mounted) return;
    setState(() {
      _progress = null;
      _failed = failed;
    });
    await _refresh();
  }

  Future<void> _delete() async {
    await _fonts.deleteAll();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ({int pages, int bytes})? totals = _totals;
    final int? onDevice = _onDevice;
    final (int, int)? progress = _progress;
    if (totals == null || onDevice == null) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(8.w, 4.h, 8.w, 8.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            LocaleKeys.mushafFontQpcFontsCount.tr(
              args: <String>[
                onDevice.toLocalisedString(),
                totals.pages.toLocalisedString(),
              ],
            ),
            style: theme.textTheme.titleSmall,
          ),
          SizedBox(height: 8.h),
          // How much of the mushaf is already here, before any fetch.
          ProgressBar(
            value: totals.pages == 0 ? 0 : onDevice / totals.pages,
            height: 5.r,
          ),
          SizedBox(height: 10.h),
          if (progress != null) ...<Widget>[
            LinearProgressIndicator(
              value: progress.$2 == 0 ? null : progress.$1 / progress.$2,
            ),
            SizedBox(height: 4.h),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    LocaleKeys.mushafFontQpcFontsDownloading.tr(
                      args: <String>[
                        progress.$1.toLocalisedString(),
                        progress.$2.toLocalisedString(),
                      ],
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _stop = true),
                  child: Text(LocaleKeys.mushafFontQpcFontsStop.tr()),
                ),
              ],
            ),
          ] else ...<Widget>[
            if (onDevice < totals.pages)
              OutlinedButton.icon(
                onPressed: _downloadAll,
                icon: const Icon(Icons.download_outlined),
                label: Text(
                  LocaleKeys.mushafFontQpcFontsDownloadAll.tr(
                    args: <String>[
                      LocaleKeys.downloadsSizeMb.tr(
                        args: <String>[megabytes(totals.bytes)],
                      ),
                    ],
                  ),
                ),
              ),
            if (onDevice > 0)
              TextButton.icon(
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline),
                label: Text(LocaleKeys.mushafFontQpcFontsDelete.tr()),
              ),
            if (_failed > 0)
              Text(
                LocaleKeys.mushafFontQpcFontsFailed.tr(
                  args: <String>[_failed.toLocalisedString()],
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
