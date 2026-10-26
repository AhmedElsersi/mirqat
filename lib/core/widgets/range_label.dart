import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';

import '../../data/models/surah.dart';
import '../../domain/entities/ayah_ref.dart';
import '../extensions/number_extensions.dart';
import '../localization/locale_keys.dart';

/// A range in words, in the reader's language and numerals: «سورة الملك
/// كاملة», «سورة البقرة · الآيات ١ - ٥», «سورة البقرة · الآية ٧», «من
/// الإخلاص ٣ إلى الفلق ٢». [fromSurah] and [toSurah] are the surahs the two
/// ends are numbered in.
String rangeLabel(
  BuildContext context, {
  required AyahRef from,
  required AyahRef to,
  required Surah fromSurah,
  required Surah toSurah,
}) {
  final bool arabic = context.locale.languageCode == 'ar';
  final String first = arabic ? fromSurah.nameAr : fromSurah.nameEn;
  if (from.surah != to.surah) {
    return LocaleKeys.sessionRangeCross.tr(
      args: <String>[
        first,
        from.ayah.toLocalisedString(),
        arabic ? toSurah.nameAr : toSurah.nameEn,
        to.ayah.toLocalisedString(),
      ],
    );
  }
  if (from.ayah == 1 && to.ayah == fromSurah.ayahCount) {
    return LocaleKeys.sessionRangeWhole.tr(args: <String>[first]);
  }
  if (from.ayah == to.ayah) {
    return LocaleKeys.sessionRangeSingle.tr(
      args: <String>[first, from.ayah.toLocalisedString()],
    );
  }
  return LocaleKeys.sessionRangeSame.tr(
    args: <String>[
      first,
      from.ayah.toLocalisedString(),
      to.ayah.toLocalisedString(),
    ],
  );
}
