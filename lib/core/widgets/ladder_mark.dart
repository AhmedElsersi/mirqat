import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../theme/app_colors.dart';

/// The app's own progress mark: the logo's rungs, small. Four rungs climbing
/// to the upper left — forward, for an Arabic reader, whatever the interface
/// language — the ones below [current] stood on, [current] gold, the rest
/// still to reach (docs/BRAND_GUIDE.md §3).
///
/// A place on the ladder, not a score: it says where something stands, never
/// how well or how often.
class LadderMark extends StatelessWidget {
  const LadderMark({
    required this.current,
    this.rungs = 4,
    this.color,
    super.key,
  });

  /// The rung reached, 0-based; [rungs] or more for a ladder climbed whole.
  final int current;
  final int rungs;

  /// The colour of the rungs not yet reached — the default is the theme's
  /// outline; on a filled surface, something that shows on it.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color done = dark ? AppColors.sabrDark : AppColors.sabrLight;
    final Color ahead = color ?? theme.colorScheme.outline;
    final double width = 24.r;
    final double step = 4.r;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: width + step * (rungs - 1),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            // Top rung first: drawn from the top down, each further right.
            for (int i = rungs - 1; i >= 0; i--)
              Padding(
                padding: EdgeInsetsDirectional.only(
                  top: i == rungs - 1 ? 0 : 3.r,
                  end: step * i,
                ),
                child: Container(
                  width: width,
                  height: 5.r,
                  decoration: BoxDecoration(
                    color: i < current
                        ? done
                        : i == current
                        ? AppColors.gold
                        : ahead,
                    borderRadius: BorderRadius.circular(3.r),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A session's rungs as a row of segments: the steps stood on, the one being
/// climbed (gold), and those still ahead.
class StepsBar extends StatelessWidget {
  const StepsBar({required this.total, required this.current, super.key});

  final int total;

  /// The step being climbed, 0-based.
  final int current;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color done = dark ? AppColors.sabrDark : AppColors.sabrLight;
    // Past a few dozen steps a segment each is a texture, not a count: the
    // row then fills as a bar.
    if (total > 40) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(2.r),
        child: LinearProgressIndicator(
          value: total == 0 ? 0 : (current + 1) / total,
          minHeight: 4.r,
          color: done,
          backgroundColor: theme.colorScheme.outline,
        ),
      );
    }
    return Row(
      children: <Widget>[
        for (int i = 0; i < total; i++) ...<Widget>[
          if (i > 0) SizedBox(width: 3.r),
          Expanded(
            child: Container(
              height: 4.r,
              decoration: BoxDecoration(
                color: i < current
                    ? done
                    : i == current
                    ? AppColors.gold
                    : theme.colorScheme.outline,
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
