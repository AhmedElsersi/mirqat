import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';

/// «مواضع ضعف: ٣» — ayahs of this surah the reader has marked *I stumble
/// here*, with the flag the Weak spots screen carries.
///
/// A tag on the surah's own pill, the flag and its count in the error tone
/// the Weak spots screen marks a stumble with (design 02). Only the number,
/// never a word about it: it says where to look, not how the reader is doing
/// (BRAND_GUIDE §6).
class WeakSpotsMarker extends StatelessWidget {
  const WeakSpotsMarker({required this.count, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = theme.colorScheme.error;

    return Tooltip(
      message: LocaleKeys.surahListWeakSpots.tr(
        args: <String>[count.toLocalisedString()],
      ),
      child: Container(
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: 9.w,
          vertical: 2.h,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.flag_outlined, size: 12.sp, color: color),
            SizedBox(width: 4.w),
            Text(
              count.toLocalisedString(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
