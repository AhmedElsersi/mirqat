/// Typed accessors for the keys in `assets/translations/*.json`.
///
/// Every user-facing string goes through here — no literals in widgets
/// (CLAUDE.md A.3, Strings).
class LocaleKeys {
  const LocaleKeys._();

  static const String appName = 'app.name';

  static const String commonError = 'common.error';
  static const String commonRetry = 'common.retry';
  static const String commonCancel = 'common.cancel';
  static const String commonClose = 'common.close';

  static const String surahListTitle = 'surah_list.title';
  static const String surahListEmpty = 'surah_list.empty';
}
