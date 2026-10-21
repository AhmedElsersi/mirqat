import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/surah.dart';
import '../cubit/surah_list_state.dart';
import 'reading_only_marker.dart';
import 'weak_spots_marker.dart';

/// One surah in the index, on one line: its number, its name, where and how
/// long, and how much of it is memorized — a ring, tapped for the detail.
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
    final Surah surah = item.surah;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(16.w, 10.h, 8.w, 10.h),
        child: Row(
          children: <Widget>[
            NumberDiamond(number: surah.number),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    surah.nameAr,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Wrap(
                    spacing: 10.w,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Text(
                        joinDetails(<String>[
                          (surah.revelationPlace == RevelationPlace.makkah
                                  ? LocaleKeys.mushafMakki
                                  : LocaleKeys.mushafMadani)
                              .tr(),
                          LocaleKeys.surahListAyahCount.tr(
                            args: <String>[surah.ayahCount.toLocalisedString()],
                          ),
                        ]),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (item.readingOnly) const ReadingOnlyMarker(),
                      if (item.weakCount > 0)
                        WeakSpotsMarker(count: item.weakCount),
                    ],
                  ),
                ],
              ),
            ),
            SurahProgressRing(
              fraction: item.memorizedFraction,
              caption: item.isUntouched
                  ? LocaleKeys.surahListNotStarted.tr()
                  : LocaleKeys.surahListProgress.tr(
                      args: <String>[
                        item.memorizedCount.toLocalisedString(),
                        surah.ayahCount.toLocalisedString(),
                      ],
                    ),
              onTap: onProgressTap,
            ),
          ],
        ),
      ),
    );
  }
}

/// How much of a surah is memorized, as a ring: empty, filling, closed. Its
/// caption — «٢ من ٧ محفوظة» — is its tooltip and its spoken label, and a tap
/// opens the surah's progress, ayah by ayah.
class SurahProgressRing extends StatelessWidget {
  const SurahProgressRing({
    required this.fraction,
    required this.caption,
    required this.onTap,
    super.key,
  });

  final double fraction;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color done = theme.brightness == Brightness.dark
        ? AppColors.sabrDark
        : AppColors.sabrLight;
    return Tooltip(
      message: caption,
      child: InkResponse(
        onTap: onTap,
        radius: 24.r,
        child: SizedBox.square(
          dimension: 44.r,
          child: Center(
            child: SizedBox.square(
              dimension: 30.r,
              // Painted, not a progress indicator: that widget is the app's
              // "loading" spinner, and a ring here says how much, not wait.
              child: CustomPaint(
                painter: _Ring(
                  fraction: fraction,
                  color: done,
                  track: theme.colorScheme.surfaceContainerHighest,
                  width: 3.5.r,
                ),
                child: fraction >= 1
                    ? Center(
                        child: Icon(Icons.check, size: 16.r, color: done),
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Ring extends CustomPainter {
  const _Ring({
    required this.fraction,
    required this.color,
    required this.track,
    required this.width,
  });

  final double fraction;
  final Color color;
  final Color track;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect box = (Offset.zero & size).deflate(width / 2);
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(box, 0, math.pi * 2, false, stroke..color = track);
    if (fraction <= 0) return;
    canvas.drawArc(
      box,
      -math.pi / 2,
      math.pi * 2 * fraction.clamp(0.0, 1.0),
      false,
      stroke..color = color,
    );
  }

  @override
  bool shouldRepaint(_Ring old) =>
      old.fraction != fraction || old.color != color || old.track != track;
}

/// A number in a diamond — the shape of the mushaf's own ayah markers, set
/// square-on so the digits stay upright.
class NumberDiamond extends StatelessWidget {
  const NumberDiamond({required this.number, super.key});

  final int number;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SizedBox.square(
      dimension: 42.r,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: 30.r,
              height: 30.r,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8.r),
              ),
            ),
          ),
          Text(
            number.toLocalisedString(),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
