import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/theme/app_colors.dart';
import '../cubit/surah_list_state.dart';

/// The grid form of a surah: the same data as [SurahRow], laid out as a card.
///
/// Deliberately not a squashed row. A grid cell is tall and narrow, so the
/// number badge leads, the name takes the width it needs, and the progress
/// reads as a ring rather than a bar — a 5px bar in a 150px cell is a smudge.
class SurahTile extends StatelessWidget {
  const SurahTile({required this.item, required this.onTap, super.key});

  final SurahListItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsetsDirectional.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsetsDirectional.all(12.r),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  _NumberBadge(number: item.surah.number),
                  const Spacer(),
                  _ProgressRing(fraction: item.memorizedFraction),
                ],
              ),
              SizedBox(height: 10.h),
              // Flexible, not Expanded: a long name is allowed to take a
              // second line and push the counts down, rather than being
              // clipped. Ayah text is never truncated, and a surah's name is
              // held to the same standard (CLAUDE.md A.2 rule 7).
              Flexible(
                child: Text(
                  item.surah.nameAr,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                LocaleKeys.surahListAyahCount.tr(
                  args: <String>[item.surah.ayahCount.toLocalisedString()],
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(height: 2.h),
              Text(
                item.isUntouched
                    ? LocaleKeys.surahListNotStarted.tr()
                    : LocaleKeys.surahListProgress.tr(
                        args: <String>[
                          item.memorizedCount.toLocalisedString(),
                          item.surah.ayahCount.toLocalisedString(),
                        ],
                      ),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NumberBadge extends StatelessWidget {
  const _NumberBadge({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: 34.r,
      height: 34.r,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      child: Text(
        number.toLocalisedString(),
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Compact progress: a ring, which reads at tile size where a bar does not.
class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SizedBox.square(
      dimension: 26.r,
      child: Stack(
        children: [
          CircularProgressIndicator(
            value: fraction,
            strokeWidth: 3.r,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: const AlwaysStoppedAnimation<Color>(
              AppColors.statusMemorized,
            ),
          ),
          if (fraction ==1)
          Center(
            child:Icon(Icons.check_circle_outline_rounded,
            color: AppColors.statusMemorized,),
          ),
        ],
      ),
    );
  }
}
