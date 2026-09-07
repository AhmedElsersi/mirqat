import 'package:flutter/widgets.dart';

import '../constants/asset_paths.dart';

/// Locale configuration. Arabic is the product's first language, not a
/// translation of an English original (CLAUDE.md A.2 rule 4).
class AppLocalization {
  const AppLocalization._();

  static const Locale arabic = Locale('ar');
  static const Locale english = Locale('en');

  static const List<Locale> supportedLocales = <Locale>[arabic, english];

  /// The locale used on first launch and whenever the device locale is not
  /// supported.
  static const Locale startLocale = arabic;
  static const Locale fallbackLocale = english;

  static const String translationsPath = AssetPaths.translations;
}
