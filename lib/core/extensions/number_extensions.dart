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
/// Text that intl has already formatted — a time, a date — in the locale's
/// own digits.
///
/// `DateFormat` cannot be trusted with this: which digits it writes depends on
/// which date-symbol table was loaded first, and the one Flutter's
/// localizations load has no native zero for Arabic, so a time comes out as
/// 12:59 on a screen that says ٢٢ everywhere else. `NumberFormat`'s symbols
/// are intl's own, so the zero is taken from there.
extension LocalisedDigitsInText on String {
  String withLocalisedDigits() {
    final int zero = NumberFormat.decimalPattern(
      _numberLocale,
    ).symbols.ZERO_DIGIT.codeUnitAt(0);
    const int latinZero = 0x30;
    if (zero == latinZero) return this;
    return replaceAllMapped(
      RegExp('[0-9]'),
      (Match m) => String.fromCharCode(zero + m[0]!.codeUnitAt(0) - latinZero),
    );
  }
}

String get _numberLocale {
  final String locale = Intl.defaultLocale ?? 'en';
  return locale.startsWith('ar') ? 'ar_EG' : locale;
}
