import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/desktop.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/theme/quran_font.dart';
import '../../../core/widgets/ayah_text.dart';
import '../../../core/widgets/islamic_frame.dart';
import '../../../core/widgets/session_controls.dart';
import '../../../core/widgets/settings_card.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/ayah.dart';
import '../cubit/settings_cubit.dart';
import '../cubit/settings_state.dart';

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
      subtitle: ayah == null
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
  };
}
