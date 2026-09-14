import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../domain/entities/plan_step.dart';
import '../../../domain/entities/session_config.dart';

/// "Step 3 of 5 — Connecting ayahs 1-2", plus the repeat pips.
///
/// Reads differently under [ConnectMode.continuous], because "step 1 of 1"
/// tells the listener nothing: the whole range is a single step there and what
/// actually advances is the pass. So continuous leads with "Repetition 2 of 3"
/// and names the range underneath, while the drill modes keep the step count.
class StepHeader extends StatelessWidget {
  const StepHeader({
    required this.stepIndex,
    required this.stepCount,
    required this.step,
    required this.repeatIndex,
    required this.totalRepeats,
    required this.connectMode,
    super.key,
  });

  final int stepIndex;
  final int stepCount;
  final PlanStep? step;
  final int repeatIndex;
  final int totalRepeats;
  final ConnectMode connectMode;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PlanStep? current = step;

    final bool isContinuous = connectMode == ConnectMode.continuous;

    return Padding(
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: 16.w,
        vertical: 12.h,
      ),
      child: Column(
        children: <Widget>[
          Text(
            isContinuous
                ? LocaleKeys.playerRepeatHeader.tr(
                    args: <String>[
                      repeatIndex.toLocalisedString(),
                      totalRepeats.toLocalisedString(),
                    ],
                  )
                : LocaleKeys.playerStepHeader.tr(
                    args: <String>[
                      (stepIndex + 1).toLocalisedString(),
                      stepCount.toLocalisedString(),
                    ],
                  ),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: 4.h),
          if (current != null)
            Text(
              _subtitle(current, isContinuous),
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          SizedBox(height: 10.h),
          _RepeatPips(current: repeatIndex, total: totalRepeats),
        ],
      ),
    );
  }

  /// What the current step is doing, in words.
  ///
  /// Continuous never says "connecting": nothing is being joined to anything,
  /// the range is simply being recited. The ayah numbers go through
  /// `toLocalisedString` so they read in the locale's own numerals — the old
  /// connect line interpolated them raw and showed Western digits in Arabic.
  static String _subtitle(PlanStep step, bool isContinuous) {
    if (isContinuous) {
      return LocaleKeys.playerRecitingRange.tr(
        args: <String>[
          step.fromAyah.toLocalisedString(),
          step.toAyah.toLocalisedString(),
        ],
      );
    }
    if (step is LearnStep) {
      return LocaleKeys.playerLearning.tr(
        args: <String>[step.ayah.toLocalisedString()],
      );
    }
    return LocaleKeys.playerConnecting.tr(
      args: <String>[
        step.fromAyah.toLocalisedString(),
        step.toAyah.toLocalisedString(),
      ],
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
              args: <String>[current.toLocalisedString(), total.toLocalisedString()],
            ),
            style: theme.textTheme.labelLarge,
          ),
      ],
    );
  }
}
