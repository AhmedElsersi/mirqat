import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/localization/locale_keys.dart';
import '../../../domain/entities/plan_step.dart';

/// "Step 3 of 5 — Connecting ayahs 1-2", plus the repeat pips.
class StepHeader extends StatelessWidget {
  const StepHeader({
    required this.stepIndex,
    required this.stepCount,
    required this.step,
    required this.repeatIndex,
    required this.totalRepeats,
    super.key,
  });

  final int stepIndex;
  final int stepCount;
  final PlanStep? step;
  final int repeatIndex;
  final int totalRepeats;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PlanStep? current = step;

    return Padding(
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: 16.w,
        vertical: 12.h,
      ),
      child: Column(
        children: <Widget>[
          Text(
            LocaleKeys.playerStepHeader.tr(
              args: <String>['${stepIndex + 1}', '$stepCount'],
            ),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: 4.h),
          if (current != null)
            Text(
              current is LearnStep
                  ? LocaleKeys.playerLearning.tr(
                      args: <String>['${current.ayah}'],
                    )
                  : LocaleKeys.playerConnecting.tr(
                      args: <String>[
                        '${current.fromAyah}',
                        '${current.toAyah}',
                      ],
                    ),
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          SizedBox(height: 10.h),
          _RepeatPips(current: repeatIndex, total: totalRepeats),
        ],
      ),
    );
  }
}

class _RepeatPips extends StatelessWidget {
  const _RepeatPips({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        // Beyond a handful of repeats the dots stop being readable, so the
        // count takes over.
        if (total <= 8)
          for (int i = 1; i <= total; i++)
            Container(
              width: 9.r,
              height: 9.r,
              margin: EdgeInsetsDirectional.symmetric(horizontal: 3.w),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i <= current
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
            )
        else
          Text(
            LocaleKeys.playerRepeatPips.tr(
              args: <String>['$current', '$total'],
            ),
            style: theme.textTheme.labelLarge,
          ),
      ],
    );
  }
}
