import '../data/models/app_info.dart';

/// What, if anything, to say about updating.
enum UpdateKind {
  /// Nothing to say.
  none,

  /// A newer version is out. Mentioned, with a "later".
  optional,

  /// This version is older than the oldest still allowed. The app asks to be
  /// updated and does nothing else until it is.
  required,
}

/// How often an optional update may be mentioned.
const Duration kUpdatePromptInterval = Duration(days: 1);

/// Decides what to say, from the installed version, this platform's rules,
/// and when an update was last mentioned.
///
/// Every doubt is resolved towards saying nothing. A rule with no store page
/// is ignored — a prompt whose button goes nowhere is a dead end, and a
/// *blocking* one would lock people out with no way back in. A version that
/// cannot be read, on either side, is no rule at all: a typo in a published
/// file must not be able to stop the app.
UpdateKind decideUpdate({
  required String installed,
  required PlatformUpdate rules,
  required DateTime? lastPrompted,
  required DateTime now,
}) {
  final AppVersion? current = AppVersion.tryParse(installed);
  if (current == null || rules.storeUrl.trim().isEmpty) return UpdateKind.none;

  final AppVersion? min = AppVersion.tryParse(rules.min);
  if (min != null && current < min) return UpdateKind.required;

  final AppVersion? latest = AppVersion.tryParse(rules.latest);
  if (latest == null || !(current < latest)) return UpdateKind.none;

  final bool recently =
      lastPrompted != null &&
      now.difference(lastPrompted).abs() < kUpdatePromptInterval;
  return recently ? UpdateKind.none : UpdateKind.optional;
}
