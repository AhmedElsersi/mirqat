import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../data/models/surah.dart';
import '../cubit/mushaf_page.dart';

/// What can be done with an ayah that has been long-pressed.
enum AyahAction {
  /// A session from this ayah to the end of its surah, started at once.
  playFromHere,

  /// A session over this ayah alone, started at once.
  memorizeAlone,

  /// This ayah becomes the start, or the end, of the range a session would
  /// cover. Nothing starts: the range is tinted on the page and the bar's
  /// play button takes it from there.
  rangeStart,
  rangeEnd,

  /// Gives the range back to the page on show.
  clearRange,
}

/// What a long-pressed ayah offers. Pops with the [AyahAction] chosen.
class AyahActionsSheet extends StatelessWidget {
  const AyahActionsSheet({
    required this.ayah,
    required this.surah,
    required this.canPlay,
    required this.hasChosenRange,
    super.key,
  });

  final AyahRef ayah;
  final Surah surah;

  /// Whether a session can be started at all — a surah nobody has recorded
  /// can still be read, and its range can still be marked.
  final bool canPlay;

  final bool hasChosenRange;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String surahName = context.locale.languageCode == 'ar'
        ? surah.nameAr
        : surah.nameEn;

    ListTile action(AyahAction value, IconData icon, String label) => ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: () => Navigator.of(context).pop(value),
    );

    return SafeArea(
      child: Padding(
        padding: EdgeInsetsDirectional.symmetric(vertical: 8.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: EdgeInsetsDirectional.symmetric(
                horizontal: 16.w,
                vertical: 8.h,
              ),
              child: Text(
                LocaleKeys.mushafAyahReference.tr(
                  args: <String>[surahName, ayah.ayah.toLocalisedString()],
                ),
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (canPlay) ...<Widget>[
              action(
                AyahAction.playFromHere,
                Icons.play_arrow_outlined,
                LocaleKeys.mushafPlayFromHere.tr(),
              ),
              action(
                AyahAction.memorizeAlone,
                Icons.repeat_one,
                LocaleKeys.mushafMemorizeAyah.tr(),
              ),
            ],
            action(
              AyahAction.rangeStart,
              Icons.first_page,
              LocaleKeys.mushafSetRangeStart.tr(),
            ),
            action(
              AyahAction.rangeEnd,
              Icons.last_page,
              LocaleKeys.mushafSetRangeEnd.tr(),
            ),
            if (hasChosenRange)
              action(
                AyahAction.clearRange,
                Icons.clear,
                LocaleKeys.mushafClearRange.tr(),
              ),
          ],
        ),
      ),
    );
  }
}
