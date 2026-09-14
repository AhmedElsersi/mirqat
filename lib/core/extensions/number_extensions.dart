// intl reaches us through easy_localization, which re-exports it — no new
// package enters the approved list (CLAUDE.md A.4).
import 'package:easy_localization/easy_localization.dart';

/// Numerals in the numeral system the reader's locale actually uses.
///
/// Arabic renders ٣ من ٥, English renders 3 of 5. Forcing Western digits into
/// an Arabic UI is the kind of small wrongness that makes an app feel
/// translated rather than written (docs/BRAND_GUIDE.md §6).
extension LocalisedDigits on num {
  /// The active locale's digits, grouped as that locale groups them.
  String toLocalisedString() =>
      NumberFormat.decimalPattern(_numberLocale).format(this);

  /// As [toLocalisedString], with exactly [decimals] fraction digits.
  String toLocalisedFixed(int decimals) =>
      (NumberFormat.decimalPattern(_numberLocale)
            ..minimumFractionDigits = decimals
            ..maximumFractionDigits = decimals)
          .format(this);
}

/// CLDR's plain `ar` has used Western digits since the numbering-system split,
/// so `NumberFormat('ar')` yields `3`, not `٣`. Arabic-Indic digits — along
/// with ٫ and ٬ as separators — live under `ar_EG`, which is also the launch
/// market. Any Arabic locale therefore formats through it.
String get _numberLocale {
  final String locale = Intl.defaultLocale ?? 'en';
  return locale.startsWith('ar') ? 'ar_EG' : locale;
}
