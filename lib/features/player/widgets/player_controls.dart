import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/localization/locale_keys.dart';

/// Transport controls. Large targets — this is used one-handed, often with the
/// phone on a stand.
class PlayerControls extends StatelessWidget {
  const PlayerControls({
    required this.playing,
    required this.onPlayPause,
    required this.onPreviousStep,
    required this.onNextStep,
    required this.onRestartStep,
    required this.onStop,
    super.key,
  });

  final bool playing;
  final VoidCallback onPlayPause;
  final VoidCallback onPreviousStep;
  final VoidCallback onNextStep;
  final VoidCallback onRestartStep;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: EdgeInsetsDirectional.symmetric(horizontal: 12.w, vertical: 8.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          _ControlButton(
            // Directional so the arrow points the right way in both locales.
            icon: Icons.skip_previous,
            tooltip: LocaleKeys.playerPreviousStep.tr(),
            onPressed: onPreviousStep,
          ),
          _ControlButton(
            icon: Icons.replay,
            tooltip: LocaleKeys.playerRestartStep.tr(),
            onPressed: onRestartStep,
          ),
          SizedBox(
            width: 68.r,
            height: 68.r,
            child: FilledButton(
              onPressed: onPlayPause,
              style: FilledButton.styleFrom(
                shape: const CircleBorder(),
                padding: EdgeInsetsDirectional.zero,
              ),
              child: Icon(
                playing ? Icons.pause : Icons.play_arrow,
                size: 34.r,
                semanticLabel: playing
                    ? LocaleKeys.playerPause.tr()
                    : LocaleKeys.playerPlay.tr(),
              ),
            ),
          ),
          _ControlButton(
            icon: Icons.stop,
            tooltip: LocaleKeys.playerStop.tr(),
            onPressed: onStop,
            color: theme.colorScheme.error,
          ),
          _ControlButton(
            icon: Icons.skip_next,
            tooltip: LocaleKeys.playerNextStep.tr(),
            onPressed: onNextStep,
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      iconSize: 30.r,
      color: color,
      // Comfortably past the 48dp minimum target.
      constraints: BoxConstraints.tightFor(width: 54.r, height: 54.r),
      icon: Icon(icon),
    );
  }
}
