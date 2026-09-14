import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/extensions/number_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/ayah_text.dart';
import '../../../data/models/ayah.dart';

/// The ayahs of the session range, Uthmani script.
///
/// Text is never truncated or ellipsized (CLAUDE.md A.2 rule 7): each ayah
/// wraps to as many lines as it needs and the list scrolls.
class AyahTextView extends StatelessWidget {
  const AyahTextView({
    required this.ayahs,
    required this.currentAyah,
    required this.blockFrom,
    required this.blockTo,
    required this.fontSize,
    super.key,
  });

  final List<Ayah> ayahs;

  /// The ayah sounding right now, emphasised within the block.
  final int? currentAyah;

  /// Bounds of the current step's block, washed as a whole.
  final int blockFrom;
  final int blockTo;

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: EdgeInsetsDirectional.all(16.r),
      itemCount: ayahs.length,
      itemBuilder: (BuildContext context, int index) {
        final Ayah ayah = ayahs[index];
        final bool inBlock = ayah.number >= blockFrom && ayah.number <= blockTo;
        final bool isCurrent = ayah.number == currentAyah;

        return Container(
          margin: EdgeInsetsDirectional.only(bottom: 10.h),
          padding: EdgeInsetsDirectional.symmetric(
            horizontal: 12.w,
            vertical: 10.h,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10.r),
            color: isCurrent
                ? AppColors.ayahHighlight
                : inBlock
                ? AppColors.blockHighlight
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _AyahNumber(number: ayah.number, emphasised: isCurrent),
              SizedBox(width: 10.w),
              Expanded(
                child: AyahText(
                  text: ayah.text,
                  fontSize: fontSize,
                  emphasis: isCurrent
                      ? AyahEmphasis.current
                      : inBlock
                      ? AyahEmphasis.inBlock
                      : AyahEmphasis.context,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AyahNumber extends StatelessWidget {
  const _AyahNumber({required this.number, required this.emphasised});

  final int number;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: 26.r,
      height: 26.r,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: emphasised
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHighest,
      ),
      child: Text(
        number.toLocalisedString(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: emphasised
              ? theme.colorScheme.onPrimary
              // onSurface, not onSurfaceVariant: the secondary token measures
              // 4.15:1 against surfaceContainerHighest and this is an 11sp
              // label, which is not large text.
              : theme.colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
