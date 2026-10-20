import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../data/models/app_settings.dart';
import '../localization/locale_keys.dart';
import 'session_controls.dart';

/// How much of the page is covered while reading: shown, the first word of
/// each ayah only, or the markers alone.
///
/// One widget for the session sheet and the settings page, so the two cannot
/// drift apart; both write the same setting.
class MemorizationViewControl extends StatelessWidget {
  const MemorizationViewControl({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final MemorizationView value;
  final ValueChanged<MemorizationView> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SetupSection(
      label: LocaleKeys.memorizationViewTitle.tr(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SegmentedButton<MemorizationView>(
            segments: <ButtonSegment<MemorizationView>>[
              ButtonSegment<MemorizationView>(
                value: MemorizationView.off,
                label: Text(LocaleKeys.memorizationViewOff.tr()),
              ),
              ButtonSegment<MemorizationView>(
                value: MemorizationView.firstWords,
                label: Text(LocaleKeys.memorizationViewFirstWords.tr()),
              ),
              ButtonSegment<MemorizationView>(
                value: MemorizationView.markersOnly,
                label: Text(LocaleKeys.memorizationViewMarkersOnly.tr()),
              ),
            ],
            selected: <MemorizationView>{value},
            showSelectedIcon: false,
            onSelectionChanged: (Set<MemorizationView> s) => onChanged(s.first),
          ),
          Padding(
            padding: EdgeInsetsDirectional.only(top: 6.h),
            child: Text(
              LocaleKeys.memorizationViewHint.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
