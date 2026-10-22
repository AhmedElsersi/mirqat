import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/localization/locale_keys.dart';
import '../../../core/widgets/ayah_end_field.dart';
import '../../../core/widgets/panel.dart';
import '../../../core/widgets/range_label.dart';
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

/// Each part is a card with a switch: on, it carries a range that stays until
/// it is changed; off, it is one line and no fields.
///
/// The new portion also offers the next one — the same length, beginning
/// where this one ends — because moving a wird on by hand means setting two
/// ends that the app can work out from the one that is there.
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

  /// [ref] moved on by [steps] ayahs, across surah boundaries as the mushaf
  /// runs; null once there is no more mushaf to move into.
  AyahRef? _advance(AyahRef ref, int steps) {
    int surah = ref.surah;
    int ayah = ref.ayah;
    for (int i = 0; i < steps; i++) {
      final Surah? here = _surah(surah);
      if (here == null) return null;
      if (ayah < here.ayahCount) {
        ayah += 1;
      } else {
        surah += 1;
        ayah = 1;
        if (_surah(surah) == null) return null;
      }
    }
    return AyahRef(surah, ayah);
  }

  /// The portion after [range], the same length as it.
  WirdRange? _next(WirdRange range) {
    int length = 1;
    AyahRef walk = range.from;
    while (walk < range.to) {
      final AyahRef? step = _advance(walk, 1);
      if (step == null) break;
      walk = step;
      length += 1;
    }
    final AyahRef? from = _advance(range.to, 1);
    if (from == null) return null;
    final AyahRef? to = _advance(from, length - 1);
    if (to == null) return null;
    return WirdRange(from: from, to: to);
  }

  String? _rangeLabel(WirdRange range) {
    final Surah? from = _surah(range.from.surah);
    final Surah? to = _surah(range.to.surah);
    if (from == null || to == null) return null;
    return rangeLabel(
      context,
      from: range.from,
      to: range.to,
      fromSurah: from,
      toSurah: to,
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
        // The parts scroll; "save" does not. Three parts open at once are
        // taller than a phone, and a save button that has scrolled away
        // reads as a sheet with no way out of it.
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsetsDirectional.fromSTEB(16.w, 0, 16.w, 8.h),
                  children: <Widget>[
                    Text(
                      LocaleKeys.wirdTitle.tr(),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      LocaleKeys.wirdHint.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    SizedBox(height: 14.h),
                    for (final WirdPart part in WirdPart.values) ...<Widget>[
                      _PartCard(
                        part: part,
                        range: _draft[part],
                        surahs: widget.surahs,
                        label: _draft[part] == null
                            ? null
                            : _rangeLabel(_draft[part]!),
                        next: part == WirdPart.fresh && _draft[part] != null
                            ? _next(_draft[part]!)
                            : null,
                        nextLabel:
                            part == WirdPart.fresh && _draft[part] != null
                            ? () {
                                final WirdRange? n = _next(_draft[part]!);
                                return n == null ? null : _rangeLabel(n);
                              }()
                            : null,
                        onToggled: (bool on) => setState(() {
                          if (on) {
                            _draft[part] = _starting();
                          } else {
                            _draft.remove(part);
                          }
                        }),
                        onFrom: (AyahRef r) => _setFrom(part, r),
                        onTo: (AyahRef r) => _setTo(part, r),
                        onNext: (WirdRange r) =>
                            setState(() => _draft[part] = r),
                      ),
                      SizedBox(height: 10.h),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsetsDirectional.fromSTEB(16.w, 8.h, 16.w, 12.h),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: Size(0, 50.r)),
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(Map<WirdPart, WirdRange>.of(_draft)),
                    child: Text(LocaleKeys.wirdSave.tr()),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PartCard extends StatelessWidget {
  const _PartCard({
    required this.part,
    required this.range,
    required this.surahs,
    required this.label,
    required this.next,
    required this.nextLabel,
    required this.onToggled,
    required this.onFrom,
    required this.onTo,
    required this.onNext,
  });

  final WirdPart part;
  final WirdRange? range;
  final List<Surah> surahs;

  /// The range in words, for the part that is off-screen in a closed card.
  final String? label;

  /// The portion after this one, where there is one.
  final WirdRange? next;
  final String? nextLabel;

  final ValueChanged<bool> onToggled;
  final ValueChanged<AyahRef> onFrom;
  final ValueChanged<AyahRef> onTo;
  final ValueChanged<WirdRange> onNext;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final WirdRange? r = range;

    return AppCard(
      padding: EdgeInsetsDirectional.all(14.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppTag(label: wirdPartLabel(part)),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  label ?? LocaleKeys.wirdNotSet.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Switch(value: r != null, onChanged: onToggled),
            ],
          ),
          if (r != null) ...<Widget>[
            SizedBox(height: 12.h),
            AyahEndField(
              label: LocaleKeys.sessionSetupFrom.tr(),
              surahs: surahs,
              value: r.from,
              onChanged: onFrom,
              isEnd: false,
            ),
            SizedBox(height: 12.h),
            AyahEndField(
              label: LocaleKeys.sessionSetupTo.tr(),
              surahs: <Surah>[
                for (final Surah s in surahs)
                  if (s.number >= r.from.surah) s,
              ],
              value: r.to,
              onChanged: onTo,
              isEnd: true,
            ),
            if (next != null && nextLabel != null) ...<Widget>[
              SizedBox(height: 12.h),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ActionChip(
                  avatar: const Icon(Icons.skip_next),
                  onPressed: () => onNext(next!),
                  label: Text(
                    LocaleKeys.wirdNextPortion.tr(args: <String>[nextLabel!]),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
