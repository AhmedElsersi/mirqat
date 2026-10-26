import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../domain/entities/session_config.dart';
import '../extensions/number_extensions.dart';
import '../localization/locale_keys.dart';
import 'panel.dart';

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
    final TextStyle? valueStyle = theme.textTheme.titleMedium?.copyWith(
      fontSize: 17.sp,
      fontWeight: FontWeight.w700,
    );

    // Plus where a line starts, minus where it ends — in Arabic, plus on the
    // right — as the design's stepper has them.
    return Container(
      padding: EdgeInsetsDirectional.all(4.r),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: Row(
        children: <Widget>[
          _stepButton(icon: Icons.add, direction: 1),
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
          _stepButton(icon: Icons.remove, direction: -1),
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
        iconSize: 22.r,
        style: IconButton.styleFrom(
          minimumSize: Size(42.r, 42.r),
          fixedSize: Size(42.r, 42.r),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11.r),
          ),
        ),
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

/// "9 rungs, 27 recitations, about 14 min", recomputed on every change: one
/// quiet line over the button that starts it.
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

    return Text(
      LocaleKeys.sessionSetupSummary.tr(
        args: <String>[
          stepCount.toLocalisedString(),
          unitCount.toLocalisedString(),
          duration,
        ],
      ),
      textAlign: TextAlign.center,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
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

/// Rows in one bordered card with a hairline between them — the design's
/// `.list`.
class SessionListCard extends StatelessWidget {
  const SessionListCard({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < children.length; i++) ...<Widget>[
          if (i > 0) const Divider(height: 1),
          children[i],
        ],
      ],
    ),
  );
}

/// One row of a [SessionListCard]: its icon, a title, an optional quiet line
/// under it, and whatever closes the row — a switch, a value, a chevron.
class SessionListRow extends StatelessWidget {
  const SessionListRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: 60.r),
        child: Padding(
          padding: EdgeInsetsDirectional.symmetric(
            horizontal: 14.w,
            vertical: 10.h,
          ),
          child: Row(
            children: <Widget>[
              TileIcon(icon),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: theme.textTheme.titleSmall),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        subtitle!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...<Widget>[
                SizedBox(width: 8.w),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A [SessionListRow] that is a switch: the whole row toggles it.
class SessionSwitchRow extends StatelessWidget {
  const SessionSwitchRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SessionListRow(
    icon: icon,
    title: title,
    subtitle: subtitle,
    onTap: () => onChanged(!value),
    trailing: Switch.adaptive(value: value, onChanged: onChanged),
  );
}

/// The controls that mean the same thing whether they are being set as a
/// default or overridden for one session, in the one order both screens
/// share: the two numbers, how the ayahs join, then the switches.
///
/// The ayah range is deliberately *not* here. In settings it is a policy
/// ("whole surah" / "last used"); in the reader it is two concrete ayah
/// numbers tied to a live selection. Forcing both through one widget would
/// mean a range control that is sometimes a policy and sometimes a number.
/// What follows the switches — the session sheet's fold of reciter and audio,
/// the settings page's closing pass and isti'adhah — is handed in as [rows],
/// and joins the same card.
class SessionTuningControls extends StatelessWidget {
  const SessionTuningControls({
    required this.repeatCount,
    required this.connectMode,
    required this.recallRounds,
    required this.chainRecall,
    required this.onRepeatCount,
    required this.onConnectMode,
    required this.onRecallRounds,
    required this.onChainRecall,
    this.rows = const <Widget>[],
    super.key,
  });

  final int repeatCount;
  final ConnectMode connectMode;

  /// How many times each ayah is asked back after its learn step
  /// ([SessionConfig.recallRounds]). 0 is off.
  final int recallRounds;

  /// Whether the session closes by testing each link — "what comes next?"
  /// ([SessionConfig.chainRecall]).
  final bool chainRecall;

  final ValueChanged<int> onRepeatCount;
  final ValueChanged<ConnectMode> onConnectMode;
  final ValueChanged<int> onRecallRounds;
  final ValueChanged<bool> onChainRecall;

  /// More rows for the card the chain-recall switch opens.
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // Recall belongs to the drill modes: continuous has no per-ayah step for
    // a recall to follow, so the control is not offered under it rather than
    // offered and ignored.
    final bool offersRecall = connectMode != ConnectMode.continuous;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // The two numbers a session is usually opened to change, side by side.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  FieldLabel(LocaleKeys.sessionSetupRepeatCount.tr()),
                  StepperField(
                    value: repeatCount,
                    min: SessionConfig.minRepeatCount,
                    max: SessionConfig.maxRepeatCount,
                    formatValue: (int v) => v.toLocalisedString(),
                    editable: true,
                    onChanged: onRepeatCount,
                  ),
                ],
              ),
            ),
            if (offersRecall) ...<Widget>[
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    FieldLabel(LocaleKeys.sessionSetupRecallRounds.tr()),
                    StepperField(
                      value: recallRounds,
                      min: SessionConfig.minRecallRounds,
                      max: SessionConfig.maxRecallRounds,
                      formatValue: (int v) => v.toLocalisedString(),
                      onChanged: onRecallRounds,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),

        // The way of joining, with what it means in one line.
        FieldLabel(LocaleKeys.sessionSetupConnectMode.tr()),
        SegmentedButton<ConnectMode>(
          showSelectedIcon: false,
          segments: <ButtonSegment<ConnectMode>>[
            for (final ConnectMode mode in ConnectMode.values)
              ButtonSegment<ConnectMode>(
                value: mode,
                label: Text(
                  mode.labelKey.tr(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          selected: <ConnectMode>{connectMode},
          onSelectionChanged: (Set<ConnectMode> picked) =>
              onConnectMode(picked.first),
        ),
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(4.w, 8.h, 4.w, 0),
          child: Text(
            connectMode.hintKey.tr(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),

        SizedBox(height: 16.h),
        SessionListCard(
          children: <Widget>[
            SessionSwitchRow(
              icon: Icons.link,
              title: LocaleKeys.sessionSetupChainRecall.tr(),
              subtitle: LocaleKeys.sessionSetupChainRecallHint.tr(),
              value: chainRecall,
              onChanged: onChainRecall,
            ),
            ...rows,
          ],
        ),
      ],
    );
  }
}

/// A speed as the design writes it: «١٫٠×», two places only where a quarter
/// step needs them.
String speedLabel(double speed) {
  final bool whole = ((speed * 10).round() - speed * 10).abs() < 1e-6;
  return '${speed.toLocalisedFixed(whole ? 1 : 2)}×';
}

/// What a session sounds like once it is tuned: how fast, and how long it
/// waits. Two rows that say where they stand; a tap on either opens its
/// sliders beneath it.
class SpeedAndPausesList extends StatefulWidget {
  const SpeedAndPausesList({
    required this.intraBlockPauseMs,
    required this.betweenRepeatPauseMs,
    required this.betweenStepsPauseMs,
    required this.playbackSpeed,
    required this.onIntraBlockPause,
    required this.onBetweenRepeatPause,
    required this.onBetweenStepsPause,
    required this.onPlaybackSpeed,
    super.key,
  });

  final int intraBlockPauseMs;
  final int betweenRepeatPauseMs;
  final int betweenStepsPauseMs;
  final double playbackSpeed;
  final ValueChanged<int> onIntraBlockPause;
  final ValueChanged<int> onBetweenRepeatPause;
  final ValueChanged<int> onBetweenStepsPause;
  final ValueChanged<double> onPlaybackSpeed;

  @override
  State<SpeedAndPausesList> createState() => _SpeedAndPausesListState();
}

class _SpeedAndPausesListState extends State<SpeedAndPausesList> {
  bool _speedOpen = false;
  bool _pausesOpen = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? value = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    String ms(int value) => LocaleKeys.sessionSetupMilliseconds.tr(
      args: <String>[value.toLocalisedString()],
    );
    final bool silent =
        widget.intraBlockPauseMs == 0 &&
        widget.betweenRepeatPauseMs == 0 &&
        widget.betweenStepsPauseMs == 0;
    final String pauses = silent
        ? LocaleKeys.sessionSetupPausesNone.tr()
        : LocaleKeys.sessionSetupPausesShort.tr(
            args: <String>[
              <int>[
                widget.intraBlockPauseMs,
                widget.betweenRepeatPauseMs,
                widget.betweenStepsPauseMs,
              ].map((int v) => v.toLocalisedString()).join(' / '),
            ],
          );
    Widget sliders(List<Widget> children) => Padding(
      padding: EdgeInsetsDirectional.fromSTEB(14.w, 0, 14.w, 8.h),
      child: Column(children: children),
    );

    return SessionListCard(
      children: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SessionListRow(
              icon: Icons.speed,
              title: LocaleKeys.sessionSetupPlaybackSpeed.tr(),
              trailing: Text(speedLabel(widget.playbackSpeed), style: value),
              onTap: () => setState(() => _speedOpen = !_speedOpen),
            ),
            if (_speedOpen)
              sliders(<Widget>[
                LabelledSlider(
                  label: LocaleKeys.sessionSetupPlaybackSpeed.tr(),
                  value: widget.playbackSpeed,
                  min: SessionConfig.minPlaybackSpeed,
                  max: SessionConfig.maxPlaybackSpeed,
                  divisions: 10,
                  valueLabel: speedLabel(widget.playbackSpeed),
                  // Snapped to the nearest 0.05 so the label never shows a
                  // value the player cannot actually be set to.
                  onChanged: (double v) =>
                      widget.onPlaybackSpeed((v * 20).round() / 20),
                ),
              ]),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SessionListRow(
              icon: Icons.pause,
              title: LocaleKeys.sessionSetupPauses.tr(),
              subtitle: LocaleKeys.sessionSetupPausesHint.tr(),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(pauses, style: value),
                  Icon(
                    _pausesOpen ? Icons.expand_less : Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              onTap: () => setState(() => _pausesOpen = !_pausesOpen),
            ),
            if (_pausesOpen)
              sliders(<Widget>[
                LabelledSlider(
                  label: LocaleKeys.sessionSetupIntraBlockPause.tr(),
                  value: widget.intraBlockPauseMs.toDouble(),
                  min: 0,
                  max: 2000,
                  divisions: 20,
                  valueLabel: ms(widget.intraBlockPauseMs),
                  onChanged: (double v) => widget.onIntraBlockPause(v.round()),
                ),
                LabelledSlider(
                  label: LocaleKeys.sessionSetupBetweenRepeatPause.tr(),
                  value: widget.betweenRepeatPauseMs.toDouble(),
                  min: 0,
                  max: 3000,
                  divisions: 30,
                  valueLabel: ms(widget.betweenRepeatPauseMs),
                  onChanged: (double v) =>
                      widget.onBetweenRepeatPause(v.round()),
                ),
                LabelledSlider(
                  label: LocaleKeys.sessionSetupBetweenStepsPause.tr(),
                  value: widget.betweenStepsPauseMs.toDouble(),
                  min: 0,
                  max: 5000,
                  divisions: 25,
                  valueLabel: ms(widget.betweenStepsPauseMs),
                  onChanged: (double v) =>
                      widget.onBetweenStepsPause(v.round()),
                ),
              ]),
          ],
        ),
      ],
    );
  }
}
