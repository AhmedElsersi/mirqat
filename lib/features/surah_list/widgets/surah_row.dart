import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/localization/locale_keys.dart';
import '../../../core/theme/app_colors.dart';
import '../cubit/surah_list_state.dart';

class SurahRow extends StatelessWidget {
  const SurahRow({
    required this.item,
    required this.onTap,
    required this.onProgressTap,
    super.key,
  });

  final SurahListItem item;
  final VoidCallback onTap;
  final VoidCallback onProgressTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: 16.w,
          vertical: 14.h,
        ),
        child: Row(
          children: <Widget>[
            _SurahNumberBadge(number: item.surah.number),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.surah.nameAr,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    LocaleKeys.surahListAyahCount.tr(
                      args: <String>['${item.surah.ayahCount}'],
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4.r),
                    child: LinearProgressIndicator(
                      value: item.memorizedFraction,
                      minHeight: 5.h,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.statusMemorized,
                      ),
                    ),
                  ),
                  SizedBox(height: 6.h),
                  Text(
                    item.isUntouched
                        ? LocaleKeys.surahListNotStarted.tr()
                        : LocaleKeys.surahListProgress.tr(
                            args: <String>[
                              '${item.memorizedCount}',
                              '${item.surah.ayahCount}',
                            ],
                          ),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onProgressTap,
              tooltip: LocaleKeys.progressTitle.tr(),
              icon: const Icon(Icons.grid_view_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

class _SurahNumberBadge extends StatelessWidget {
  const _SurahNumberBadge({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: 40.r,
      height: 40.r,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$number',
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
