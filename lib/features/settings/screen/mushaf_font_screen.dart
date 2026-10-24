import 'dart:async';
import 'dart:ui' as ui;

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
import '../../surah_list/widgets/surah_row.dart' show SurahProgressRing;

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
          final ThemeData theme = Theme.of(context);

          return DesktopWidth(
            child: ListView(
              padding: EdgeInsetsDirectional.all(16.r),
              children: <Widget>[
                _Preview(
                  ayah: sample,
                  font: settings.quranFont,
                  fontSize: settings.arabicFontSize,
                ),
                FieldLabel(LocaleKeys.mushafFontFace.tr()),
                AppCard(
                  padding: EdgeInsetsDirectional.zero,
                  child: RadioGroup<QuranFont>(
                    groupValue: settings.quranFont,
                    onChanged: (QuranFont? f) {
                      if (f != null) cubit.setQuranFont(f);
                    },
                    child: Column(
                      children: <Widget>[
                        for (final QuranFont font
                            in QuranFont.values) ...<Widget>[
                          if (font != QuranFont.values.first)
                            const Divider(height: 1),
                          _FontOption(
                            font: font,
                            chosen: font == settings.quranFont,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 10.h),
                AppNote(
                  LocaleKeys.mushafFontOnlyMatching.tr(),
                  icon: Icons.verified_user_outlined,
                ),
                // The size: its label and its value on one line, the slider
                // under them, and in one line what a bigger size does.
                Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(4.w, 20.h, 4.w, 4.h),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          LocaleKeys.mushafFontSize.tr(),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      AppTag(
                        label: settings.arabicFontSize.toLocalisedFixed(0),
                      ),
                    ],
                  ),
                ),
                // The default — where the printed page is reproduced line for
                // line — is the one tick on the track, so the way back to it
                // is seen rather than read.
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    tickMarkShape: _DefaultTick(
                      value: settings.arabicFontSize,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  child: Slider(
                    value: settings.arabicFontSize,
                    min: AppSettings.minArabicFontSize,
                    max: AppSettings.maxArabicFontSize,
                    divisions: 11,
                    label: settings.arabicFontSize.toLocalisedFixed(0),
                    onChanged: (double v) =>
                        cubit.setArabicFontSize(v.roundToDouble()),
                  ),
                ),
                Padding(
                  padding: EdgeInsetsDirectional.symmetric(horizontal: 4.w),
                  child: Text(
                    LocaleKeys.mushafFontSizeHint.tr(
                      args: <String>[
                        AppSettings.defaultArabicFontSize.toLocalisedFixed(0),
                      ],
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (settings.quranFont.pageFonts) ...<Widget>[
                  FieldLabel(LocaleKeys.mushafFontQpcFontsTitle.tr()),
                  AppCard(
                    padding: EdgeInsetsDirectional.all(16.r),
                    child: const _QpcFonts(),
                  ),
                ],
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

/// One face, named, as a row: a radio at its start, and under the name a
/// word on where its pages come from.
class _FontOption extends StatelessWidget {
  const _FontOption({required this.font, required this.chosen});

  final QuranFont font;
  final bool chosen;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? hint = font.pageFonts
        ? LocaleKeys.mushafFontQpcV2Hint.tr()
        : font == QuranFont.values.first
        ? LocaleKeys.mushafFontDefaultHint.tr()
        : null;
    return RadioListTile<QuranFont>(
      contentPadding: EdgeInsetsDirectional.fromSTEB(8.w, 4.h, 16.w, 4.h),
      value: font,
      title: Text(_nameKey(font).tr(), style: theme.textTheme.titleSmall),
      subtitle: hint == null
          ? null
          : Text(
              hint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
    );
  }

  static String _nameKey(QuranFont font) => switch (font) {
    QuranFont.hafsV22 => LocaleKeys.mushafFontHafsV22Name,
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
    final double share = totals.pages == 0 ? 0 : onDevice / totals.pages;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  Text(
                    LocaleKeys.mushafFontQpcFontsSizeHint.tr(
                      args: <String>[
                        LocaleKeys.downloadsSizeMb.tr(
                          args: <String>[megabytes(totals.bytes)],
                        ),
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
            SurahProgressRing(
              fraction: share,
              caption: LocaleKeys.mushafFontQpcFontsCount.tr(
                args: <String>[
                  onDevice.toLocalisedString(),
                  totals.pages.toLocalisedString(),
                ],
              ),
              diameter: 34.r,
            ),
          ],
        ),
        SizedBox(height: 12.h),
        // How much of the mushaf is already here, before any fetch.
        ProgressBar(value: share),
        SizedBox(height: 12.h),
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
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurfaceVariant,
              ),
              onPressed: _delete,
              child: Text(LocaleKeys.mushafFontQpcFontsDelete.tr()),
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
    );
  }
}

/// The slider's one tick: at the default size, where the page is drawn as
/// printed. Every other division is left unmarked.
///
/// A tick shape is not told which division it is drawing, so it works that
/// out from where it stands against the thumb, whose value is known.
class _DefaultTick extends SliderTickMarkShape {
  const _DefaultTick({required this.value, required this.color});

  /// The slider's current value — where the thumb is.
  final double value;
  final Color color;

  static double _fraction(double v) =>
      (v - AppSettings.minArabicFontSize) /
      (AppSettings.maxArabicFontSize - AppSettings.minArabicFontSize);

  @override
  Size getPreferredSize({
    required SliderThemeData sliderTheme,
    required bool isEnabled,
  }) => Size(2.r, 12.r);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required ui.TextDirection textDirection,
    required Offset thumbCenter,
    required bool isEnabled,
  }) {
    final Rect track =
        (sliderTheme.trackShape ?? const RoundedRectSliderTrackShape())
            .getPreferredRect(
              parentBox: parentBox,
              sliderTheme: sliderTheme,
              isEnabled: isEnabled,
              isDiscrete: true,
            );
    if (track.width <= 0) return;
    final double shift = (center.dx - thumbCenter.dx) / track.width;
    final double here =
        _fraction(value) +
        (textDirection == ui.TextDirection.rtl ? -shift : shift);
    if ((here - _fraction(AppSettings.defaultArabicFontSize)).abs() > 0.01) {
      return;
    }
    final Size size = getPreferredSize(
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
    );
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center,
          width: size.width,
          height: size.height,
        ),
        Radius.circular(1.r),
      ),
      Paint()..color = color,
    );
  }
}
