import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/localization/locale_keys.dart';
import '../../../core/widgets/ayah_end_field.dart';
import '../../../data/models/surah.dart';
import '../../../domain/entities/ayah_ref.dart';
import '../../../domain/entities/daily_wird.dart';
import 'wird_card.dart' show wirdPartLabel;

/// Sets the three parts of today's wird. Answers the wird as edited, or null
/// when the reader closes it without saving.
Future<DailyWird?> showWirdEditor(
  BuildContext context, {
  required DailyWird wird,
  required List<Surah> surahs,
}) => showModalBottomSheet<DailyWird>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => WirdEditor(wird: wird, surahs: surahs),
);

class WirdEditor extends StatefulWidget {
  const WirdEditor({required this.wird, required this.surahs, super.key});

  final DailyWird wird;
  final List<Surah> surahs;

  @override
  State<WirdEditor> createState() => _WirdEditorState();
}

class _WirdEditorState extends State<WirdEditor> {
  late final Map<WirdPart, WirdRange> _draft = <WirdPart, WirdRange>{
    ...widget.wird,
  };

  Surah? _surah(int n) =>
      n >= 1 && n <= widget.surahs.length ? widget.surahs[n - 1] : null;

  AyahRef _clamped(AyahRef ref) {
    final Surah? s = _surah(ref.surah);
    return s == null ? ref : AyahRef(s.number, ref.ayah.clamp(1, s.ayahCount));
  }

  /// A part newly added starts as the first surah, whole; the reader moves
  /// it from there.
  WirdRange _starting() {
    final Surah first = widget.surahs.first;
    return WirdRange(
      from: AyahRef(first.number, 1),
      to: AyahRef(first.number, first.ayahCount),
    );
  }

  void _setFrom(WirdPart part, AyahRef ref) {
    final WirdRange r = _draft[part]!;
    final AyahRef from = _clamped(ref);
    setState(
      () => _draft[part] = WirdRange(from: from, to: r.to < from ? from : r.to),
    );
  }

  void _setTo(WirdPart part, AyahRef ref) {
    final WirdRange r = _draft[part]!;
    final AyahRef to = _clamped(ref);
    setState(
      () => _draft[part] = WirdRange(from: to < r.from ? to : r.from, to: to),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsetsDirectional.fromSTEB(16.w, 0, 16.w, 16.h),
          children: <Widget>[
            Text(LocaleKeys.wirdTitle.tr(), style: theme.textTheme.titleLarge),
            SizedBox(height: 4.h),
            Text(
              LocaleKeys.wirdHint.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            for (final WirdPart part in WirdPart.values) ...<Widget>[
              const Divider(height: 24),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      wirdPartLabel(part),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (_draft[part] == null)
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _draft[part] = _starting()),
                      icon: const Icon(Icons.playlist_add),
                      label: Text(LocaleKeys.wirdAdd.tr()),
                    )
                  else
                    TextButton.icon(
                      onPressed: () => setState(() => _draft.remove(part)),
                      icon: const Icon(Icons.close),
                      label: Text(LocaleKeys.wirdRemove.tr()),
                    ),
                ],
              ),
              if (_draft[part] case final WirdRange range) ...<Widget>[
                SizedBox(height: 8.h),
                AyahEndField(
                  label: LocaleKeys.sessionSetupFrom.tr(),
                  surahs: widget.surahs,
                  value: range.from,
                  onChanged: (AyahRef r) => _setFrom(part, r),
                  isEnd: false,
                ),
                SizedBox(height: 12.h),
                AyahEndField(
                  label: LocaleKeys.sessionSetupTo.tr(),
                  surahs: <Surah>[
                    for (final Surah s in widget.surahs)
                      if (s.number >= range.from.surah) s,
                  ],
                  value: range.to,
                  onChanged: (AyahRef r) => _setTo(part, r),
                  isEnd: true,
                ),
              ],
            ],
            SizedBox(height: 20.h),
            FilledButton(
              onPressed: () => Navigator.of(
                context,
              ).pop(Map<WirdPart, WirdRange>.of(_draft)),
              child: Text(LocaleKeys.wirdSave.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
