import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/localization/locale_keys.dart';

/// Section heading inside the setup form.
class SetupSection extends StatelessWidget {
  const SetupSection({required this.label, required this.child, super.key});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: EdgeInsetsDirectional.only(bottom: 20.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: 8.h),
          child,
        ],
      ),
    );
  }
}

/// Minus / value / plus. Large targets — this is used one-handed.
class StepperField extends StatelessWidget {
  const StepperField({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.formatValue,
    this.step = 1,
    super.key,
  });

  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;
  final String Function(int)? formatValue;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            iconSize: 26.r,
            onPressed: value - step >= min
                ? () => onChanged(value - step)
                : null,
            icon: const Icon(Icons.remove),
          ),
          Expanded(
            child: Text(
              formatValue?.call(value) ?? '$value',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
          IconButton(
            iconSize: 26.r,
            onPressed: value + step <= max
                ? () => onChanged(value + step)
                : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

/// A labelled slider for the millisecond pauses and the playback speed.
class LabelledSlider extends StatelessWidget {
  const LabelledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.valueLabel,
    required this.onChanged,
    this.divisions,
    super.key,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String valueLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Flexible(child: Text(label, style: theme.textTheme.bodyMedium)),
            Text(
              valueLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// The connect-mode picker. Each option carries its own one-line explanation,
/// because the difference between them is the whole method.
class ConnectModeOption extends StatelessWidget {
  const ConnectModeOption({
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.r),
      child: Container(
        margin: EdgeInsetsDirectional.only(bottom: 8.h),
        padding: EdgeInsetsDirectional.all(12.r),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
            width: selected ? 2 : 1,
          ),
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.06)
              : null,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              size: 22.r,
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(label, style: theme.textTheme.bodyLarge),
                  SizedBox(height: 2.h),
                  Text(
                    hint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "5 steps · 24 recitations · 4 min 12 s", recomputed on every change.
class SessionSummary extends StatelessWidget {
  const SessionSummary({
    required this.stepCount,
    required this.unitCount,
    required this.duration,
    super.key,
  });

  final int stepCount;
  final int unitCount;
  final String duration;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: EdgeInsetsDirectional.all(14.r),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Text(
        LocaleKeys.sessionSetupSummary.tr(
          args: <String>['$stepCount', '$unitCount', duration],
        ),
        textAlign: TextAlign.center,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
