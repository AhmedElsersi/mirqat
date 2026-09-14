import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/plan_step.dart';

/// Collapsible list of every step, with the finished ones checked off.
class PlanTimeline extends StatelessWidget {
  const PlanTimeline({
    required this.steps,
    required this.currentStepIndex,
    super.key,
  });

  final List<PlanStep> steps;
  final int currentStepIndex;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Theme(
      data: theme.copyWith(dividerColor: AppColors.transparent),
      child: ExpansionTile(
        title: Text(
          LocaleKeys.playerTimeline.tr(),
          style: theme.textTheme.labelLarge,
        ),
        children: <Widget>[
          SizedBox(
            height: 220.h,
            child: ListView.builder(
              padding: EdgeInsetsDirectional.only(bottom: 12.h),
              itemCount: steps.length,
              itemBuilder: (BuildContext context, int index) {
                final PlanStep step = steps[index];
                final bool done = index < currentStepIndex;
                final bool current = index == currentStepIndex;

                return ListTile(
                  dense: true,
                  leading: Icon(
                    done
                        ? Icons.check_circle
                        : current
                        ? Icons.play_circle_fill
                        : Icons.radio_button_unchecked,
                    color: done
                        ? theme.colorScheme.primary
                        : current
                        ? theme.colorScheme.secondary
                        : theme.colorScheme.outline,
                    size: 20.r,
                  ),
                  title: Text(
                    step is LearnStep
                        ? LocaleKeys.playerLearning.tr(
                            args: <String>[step.ayah.toLocalisedString()],
                          )
                        : LocaleKeys.playerConnecting.tr(
                            args: <String>[
                              '${step.fromAyah}',
                              '${step.toAyah}',
                            ],
                          ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: current ? FontWeight.w700 : FontWeight.w400,
                      color: done
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                  trailing: Text(
                    '×${step.repeats}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
