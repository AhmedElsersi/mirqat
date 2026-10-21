import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';

/// «مواضع ضعف: ٣» — ayahs of this surah the reader has marked *I stumble
/// here*, with the flag the Weak spots screen carries.
///
/// As quiet as the reading-only marker beside it: the muted tone, never a
/// warning colour. It says where to look, not how the reader is doing
/// (BRAND_GUIDE §6).
class WeakSpotsMarker extends StatelessWidget {
  const WeakSpotsMarker({required this.count, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = theme.colorScheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.flag_outlined, size: 12.sp, color: color),
        SizedBox(width: 4.w),
        // Flexible so a narrow grid tile at a large text scale wraps the
        // label instead of overflowing.
        Flexible(
          child: Text(
            LocaleKeys.surahListWeakSpots.tr(
              args: <String>[count.toLocalisedString()],
            ),
            style: theme.textTheme.labelSmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
