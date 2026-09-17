import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/localization/locale_keys.dart';

/// «قراءة فقط» — no reciter has audio for this surah yet.
///
/// Deliberately quiet: the same muted tone as the ayah count beside it. The
/// surah is fully readable, so nothing about the row reads as unavailable.
class ReadingOnlyMarker extends StatelessWidget {
  const ReadingOnlyMarker({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = theme.colorScheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.menu_book_outlined, size: 12.sp, color: color),
        SizedBox(width: 4.w),
        // Flexible so a narrow grid tile at a large text scale wraps the
        // label instead of overflowing.
        Flexible(
          child: Text(
            LocaleKeys.surahListReadingOnly.tr(),
            style: theme.textTheme.labelSmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
