import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../data/models/surah.dart';
import '../cubit/mushaf_page.dart';

/// What a tapped ayah offers. The actions are placeholders until playback
/// lands.
class AyahActionsSheet extends StatelessWidget {
  const AyahActionsSheet({required this.ayah, required this.surah, super.key});

  final AyahRef ayah;
  final Surah surah;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String surahName = context.locale.languageCode == 'ar'
        ? surah.nameAr
        : surah.nameEn;

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
            ListTile(
              enabled: false,
              leading: const Icon(Icons.play_arrow_outlined),
              title: Text(LocaleKeys.mushafPlayFromHere.tr()),
              subtitle: Text(LocaleKeys.mushafComingSoon.tr()),
            ),
            ListTile(
              enabled: false,
              leading: const Icon(Icons.repeat),
              title: Text(LocaleKeys.mushafMemorize.tr()),
              subtitle: Text(LocaleKeys.mushafComingSoon.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
