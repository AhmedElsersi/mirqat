import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../data/models/surah.dart';
import '../../domain/entities/ayah_ref.dart';
import '../extensions/number_extensions.dart';
import '../localization/locale_keys.dart';
import 'session_controls.dart';

/// One end of a range: a surah, from a list of them, and an ayah of it.
class AyahEndField extends StatelessWidget {
  const AyahEndField({
    super.key,
    required this.label,
    required this.surahs,
    required this.value,
    required this.onChanged,
    required this.isEnd,
  });

  final String label;
  final List<Surah> surahs;
  final AyahRef value;
  final ValueChanged<AyahRef> onChanged;

  /// Picking another surah means its last ayah at the far end, its first at
  /// the near one.
  final bool isEnd;

  @override
  Widget build(BuildContext context) {
    final bool arabic = context.locale.languageCode == 'ar';
    final Surah? surah = surahs
        .where((Surah s) => s.number == value.surah)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        SizedBox(height: 4.h),
        Row(
          children: <Widget>[
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<int>(
                key: ValueKey<String>(
                  '${isEnd ? 'to' : 'from'}-${surah?.number}',
                ),
                initialValue: surah?.number,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: LocaleKeys.sessionSurah.tr(),
                  isDense: true,
                ),
                items: <DropdownMenuItem<int>>[
                  for (final Surah s in surahs)
                    DropdownMenuItem<int>(
                      value: s.number,
                      child: Text(
                        '${s.number.toLocalisedString()}. '
                        '${arabic ? s.nameAr : s.nameEn}',
                      ),
                    ),
                ],
                onChanged: (int? n) {
                  if (n == null || n == value.surah) return;
                  final Surah picked = surahs.firstWhere(
                    (Surah s) => s.number == n,
                  );
                  onChanged(AyahRef(n, isEnd ? picked.ayahCount : 1));
                },
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              flex: 2,
              child: StepperField(
                value: value.ayah,
                min: 1,
                max: surah?.ayahCount ?? value.ayah,
                formatValue: (int v) => v.toLocalisedString(),
                onChanged: (int a) => onChanged(AyahRef(value.surah, a)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
