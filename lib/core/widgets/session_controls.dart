import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../domain/entities/session_config.dart';
import '../extensions/number_extensions.dart';
import '../localization/locale_keys.dart';

/// Section heading for a block of session or settings controls.
///
/// Lives in core/ rather than in a feature: the settings screen and the
/// reader's session drawer present the same controls — one as defaults, one
/// as a per-session override — so a single set of widgets keeps them from
/// drifting apart.
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
///
/// Holding either button keeps stepping, faster the longer it is held, so the
/// far end of the range is one press rather than dozens. With [editable] the
/// value is also a digits-only text field.
class StepperField extends StatefulWidget {
  const StepperField({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.formatValue,
    this.step = 1,
    this.editable = false,
    super.key,
  });

  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;
  final String Function(int)? formatValue;

  /// Whether the value can be typed as well as stepped.
  ///
  /// A typed number is applied as soon as it is in range, which suits a
  /// standalone count. Leave it off for a control whose changes nudge a
  /// sibling — the from/to ayah pickers — where the "1" on the way to "12"
  /// would drag the other end along with it.
  final bool editable;

  @override
  State<StepperField> createState() => _StepperFieldState();
}

class _StepperFieldState extends State<StepperField> {
  late final TextEditingController _controller = TextEditingController(
    text: _format(widget.value),
  );
  late final FocusNode _focus = FocusNode()..addListener(_onFocusChange);

  Timer? _holdTimer;

  /// Where a hold has got to. Tracked here rather than read back from
  /// [StepperField.value], which only catches up once the parent rebuilds.
  int _heldValue = 0;

  String _format(int v) => widget.formatValue?.call(v) ?? '$v';

  @override
  void didUpdateWidget(StepperField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow changes made elsewhere — the buttons, a reset — without
    // rewriting a field that is mid-edit and already says the same number.
    if (_focus.hasFocus) {
      if (widget.value != oldWidget.value &&
          _parseDigits(_controller.text) != widget.value) {
        _setText(widget.value);
      }
    } else if (_controller.text != _format(widget.value)) {
      _setText(widget.value);
    }
  }

  @override
  void dispose() {
    _stopHold();
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  // --- press and hold -------------------------------------------------------

  void _startHold(int direction) {
    _stopHold();
    _heldValue = widget.value;
    _holdTick(direction, 0);
  }

  void _holdTick(int direction, int ticks) {
    final int next = _heldValue + direction * widget.step;
    if (next < widget.min || next > widget.max) {
      _stopHold();
      return;
    }
    _heldValue = next;
    widget.onChanged(next);
    // A readable pace to begin with, then quicker. Not quicker than this:
    // every tick rebuilds the session plan behind the control.
    final int delayMs = ticks < 5 ? 250 : (ticks < 20 ? 110 : 60);
    _holdTimer = Timer(
      Duration(milliseconds: delayMs),
      () => _holdTick(direction, ticks + 1),
    );
  }

  void _stopHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
  }

  // --- typing ---------------------------------------------------------------

  void _setText(int v) {
    final String text = _format(v);
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _onTextChanged(String text) {
    final int? typed = _parseDigits(text);
    if (typed != null &&
        typed >= widget.min &&
        typed <= widget.max &&
        typed != widget.value) {
      widget.onChanged(typed);
    }
  }

  /// Leaving the field settles whatever is left in it: an empty field goes
  /// back to the current value, an out-of-range one to the nearest bound.
  void _onFocusChange() {
    if (_focus.hasFocus) return;
    final int? typed = _parseDigits(_controller.text);
    final int settled = typed == null
        ? widget.value
        : typed.clamp(widget.min, widget.max);
    if (settled != widget.value) widget.onChanged(settled);
    _setText(settled);
  }

  /// A tap selects the whole number, so typing replaces it — otherwise "10"
  /// typed after a "3" reads as 310.
  void _selectAll() {
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? valueStyle = theme.textTheme.titleMedium;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Row(
        children: <Widget>[
          _stepButton(icon: Icons.remove, direction: -1),
          Expanded(
            child: widget.editable
                ? TextField(
                    controller: _controller,
                    focusNode: _focus,
                    textAlign: TextAlign.center,
                    style: valueStyle,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    inputFormatters: <TextInputFormatter>[
                      _DigitsFormatter(
                        zero: _digitZeroOf(_format(0)),
                        maxDigits: '${widget.max}'.length,
                      ),
                    ],
                    onChanged: _onTextChanged,
                    onTap: _selectAll,
                    // The number pad has no return key on iOS; tapping away
                    // is how the field gets closed there.
                    onTapOutside: (_) => _focus.unfocus(),
                    decoration: const InputDecoration(
                      isDense: true,
                      filled: false,
                      contentPadding: EdgeInsetsDirectional.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  )
                : Text(
                    _format(widget.value),
                    textAlign: TextAlign.center,
                    style: valueStyle,
                  ),
          ),
          _stepButton(icon: Icons.add, direction: 1),
        ],
      ),
    );
  }

  Widget _stepButton({required IconData icon, required int direction}) {
    final int next = widget.value + direction * widget.step;
    final bool enabled = next >= widget.min && next <= widget.max;

    return GestureDetector(
      onLongPressStart: (_) => _startHold(direction),
      onLongPressEnd: (_) => _stopHold(),
      onLongPressCancel: _stopHold,
      child: IconButton(
        iconSize: 26.r,
        onPressed: enabled ? () => widget.onChanged(next) : null,
        icon: Icon(icon),
      ),
    );
  }
}

/// The zero of each digit family a keyboard might send: ASCII, Arabic-Indic,
/// and the extended (Persian/Urdu) Arabic-Indic set.
const List<int> _digitZeros = <int>[0x30, 0x660, 0x6F0];

int? _digitValue(int codeUnit) {
  for (final int zero in _digitZeros) {
    if (codeUnit >= zero && codeUnit <= zero + 9) return codeUnit - zero;
  }
  return null;
}

int? _parseDigits(String text) {
  if (text.isEmpty) return null;
  int result = 0;
  for (final int unit in text.codeUnits) {
    final int? digit = _digitValue(unit);
    if (digit == null) return null;
    result = result * 10 + digit;
  }
  return result;
}

/// The digit family a formatted zero is written in, ASCII if it is not one.
int _digitZeroOf(String formattedZero) =>
    formattedZero.length == 1 && _digitValue(formattedZero.codeUnitAt(0)) == 0
    ? formattedZero.codeUnitAt(0)
    : 0x30;

/// Digits only, rewritten into one family and capped in length.
///
/// Keyboards disagree about what a digit is — an Arabic layout may send ٣
/// where an English one sends 3. Both are accepted, and both are shown in the
/// numerals the rest of the screen uses.
class _DigitsFormatter extends TextInputFormatter {
  _DigitsFormatter({required this.zero, required this.maxDigits});

  final int zero;
  final int maxDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final StringBuffer out = StringBuffer();
    for (final int unit in newValue.text.codeUnits) {
      final int? digit = _digitValue(unit);
      if (digit != null) out.writeCharCode(zero + digit);
    }
    final String text = out.toString();
    if (text.length > maxDigits) return oldValue;
    if (text == newValue.text) return newValue;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
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
          args: <String>[
            stepCount.toLocalisedString(),
            unitCount.toLocalisedString(),
            duration,
          ],
        ),
        textAlign: TextAlign.center,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// The user-facing name and one-line explanation of each connect mode.
///
/// An extension on the enum rather than a `switch` copied into each screen:
/// three screens showed the same three labels and the switches drifted, so the
/// copy now has exactly one home and adding a mode is a compile error until it
/// is named here.
extension ConnectModeCopy on ConnectMode {
  String get labelKey => switch (this) {
    ConnectMode.cumulative => LocaleKeys.sessionSetupConnectCumulative,
    ConnectMode.continuous => LocaleKeys.sessionSetupConnectContinuous,
    ConnectMode.none => LocaleKeys.sessionSetupConnectNone,
  };

  String get hintKey => switch (this) {
    ConnectMode.cumulative => LocaleKeys.sessionSetupConnectCumulativeHint,
    ConnectMode.continuous => LocaleKeys.sessionSetupConnectContinuousHint,
    ConnectMode.none => LocaleKeys.sessionSetupConnectNoneHint,
  };
}

/// The controls that mean the same thing whether they are being set as a
/// default or overridden for one session: how many repeats, how the ayahs join,
/// how long the gaps are, how fast the recitation runs.
///
/// The ayah range is deliberately *not* here. In settings it is a policy
/// ("whole surah" / "last used"); in the reader it is two concrete ayah
/// numbers tied to a live selection. Forcing both through one widget would
/// mean a range control that is sometimes a policy and sometimes a number.
class SessionTuningControls extends StatelessWidget {
  const SessionTuningControls({
    required this.repeatCount,
    required this.connectMode,
    required this.intraBlockPauseMs,
    required this.betweenRepeatPauseMs,
    required this.betweenStepsPauseMs,
    required this.playbackSpeed,
    required this.finalFullPass,
    required this.onRepeatCount,
    required this.onConnectMode,
    required this.onIntraBlockPause,
    required this.onBetweenRepeatPause,
    required this.onBetweenStepsPause,
    required this.onPlaybackSpeed,
    required this.onFinalFullPass,
    super.key,
  });

  final int repeatCount;
  final ConnectMode connectMode;
  final int intraBlockPauseMs;
  final int betweenRepeatPauseMs;
  final int betweenStepsPauseMs;
  final double playbackSpeed;

  /// Whether the session closes with one more pass over the whole range.
  final bool finalFullPass;

  final ValueChanged<int> onRepeatCount;
  final ValueChanged<ConnectMode> onConnectMode;
  final ValueChanged<int> onIntraBlockPause;
  final ValueChanged<int> onBetweenRepeatPause;
  final ValueChanged<int> onBetweenStepsPause;
  final ValueChanged<double> onPlaybackSpeed;
  final ValueChanged<bool> onFinalFullPass;

  @override
  Widget build(BuildContext context) {
    String ms(int value) => LocaleKeys.sessionSetupMilliseconds.tr(
      args: <String>[value.toLocalisedString()],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SetupSection(
          label: LocaleKeys.sessionSetupRepeatCount.tr(),
          child: StepperField(
            value: repeatCount,
            min: SessionConfig.minRepeatCount,
            max: SessionConfig.maxRepeatCount,
            formatValue: (int v) => v.toLocalisedString(),
            editable: true,
            onChanged: onRepeatCount,
          ),
        ),
        SetupSection(
          label: LocaleKeys.sessionSetupConnectMode.tr(),
          child: Column(
            children: <Widget>[
              for (final ConnectMode mode in ConnectMode.values)
                ConnectModeOption(
                  label: mode.labelKey.tr(),
                  hint: mode.hintKey.tr(),
                  selected: connectMode == mode,
                  onTap: () => onConnectMode(mode),
                ),
            ],
          ),
        ),
        SetupSection(
          label: LocaleKeys.settingsDefaultPauses.tr(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              LabelledSlider(
                label: LocaleKeys.sessionSetupIntraBlockPause.tr(),
                value: intraBlockPauseMs.toDouble(),
                min: 0,
                max: 2000,
                divisions: 20,
                valueLabel: ms(intraBlockPauseMs),
                onChanged: (double v) => onIntraBlockPause(v.round()),
              ),
              LabelledSlider(
                label: LocaleKeys.sessionSetupBetweenRepeatPause.tr(),
                value: betweenRepeatPauseMs.toDouble(),
                min: 0,
                max: 3000,
                divisions: 30,
                valueLabel: ms(betweenRepeatPauseMs),
                onChanged: (double v) => onBetweenRepeatPause(v.round()),
              ),
              LabelledSlider(
                label: LocaleKeys.sessionSetupBetweenStepsPause.tr(),
                value: betweenStepsPauseMs.toDouble(),
                min: 0,
                max: 5000,
                divisions: 25,
                valueLabel: ms(betweenStepsPauseMs),
                onChanged: (double v) => onBetweenStepsPause(v.round()),
              ),
            ],
          ),
        ),
        SetupSection(
          label: LocaleKeys.sessionSetupPlaybackSpeed.tr(),
          child: LabelledSlider(
            label: LocaleKeys.sessionSetupPlaybackSpeed.tr(),
            value: playbackSpeed,
            min: SessionConfig.minPlaybackSpeed,
            max: SessionConfig.maxPlaybackSpeed,
            divisions: 10,
            valueLabel: '${playbackSpeed.toLocalisedFixed(2)}\u00D7',
            // Snapped to the nearest 0.05 so the label never shows a value the
            // player cannot actually be set to.
            onChanged: (double v) => onPlaybackSpeed((v * 20).round() / 20),
          ),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsetsDirectional.zero,
          title: Text(LocaleKeys.sessionSetupFinalFullPass.tr()),
          value: finalFullPass,
          onChanged: onFinalFullPass,
        ),
      ],
    );
  }
}
