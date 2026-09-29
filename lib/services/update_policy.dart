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

/// How often an optional update may be mentioned, unless the rules say
/// otherwise (`remindAfterDays`).
const Duration kUpdatePromptInterval = Duration(
  days: UpdateRules.defaultRemindAfterDays,
);

/// Whether the installed release — [version], and [build] where the platform
/// says — is older than the one a rule names.
///
/// A rule is a version, and optionally a build of it. Versions decide first;
/// only when they are equal, and both sides name a build, does the build
/// decide. A rule with no readable version is no rule, whatever build it
/// names: a typo must never lock anyone out. A rule with a version and a
/// build against an install whose build is unknown compares by version alone.
bool isOlderThan({
  required AppVersion version,
  required int? build,
  required String ruleVersion,
  required int? ruleBuild,
}) {
  final AppVersion? rule = AppVersion.tryParse(ruleVersion);
  if (rule == null) return false;
  if (version < rule) return true;
  if (rule < version) return false;
  return build != null && ruleBuild != null && build < ruleBuild;
}

/// Decides what to say, from the installed release, this platform's rules,
/// and when an update was last mentioned.
///
/// Every doubt is resolved towards saying nothing. A rule with no store page
/// is ignored — a prompt whose button goes nowhere is a dead end, and a
/// *blocking* one would lock people out with no way back in. A version that
/// cannot be read, on either side, is no rule at all: a typo in a published
/// file must not be able to stop the app. A build *ahead* of the store is
/// left alone.
///
/// Below the minimum the update is required. Below the latest it is optional
/// and can be put off for [remindAfter] — unless the latest is [PlatformUpdate.force]d,
/// which makes it required too, with no "later".
UpdateKind decideUpdate({
  required String installed,
  String installedBuild = '',
  required PlatformUpdate rules,
  required DateTime? lastPrompted,
  required DateTime now,
  Duration remindAfter = kUpdatePromptInterval,
}) {
  final AppVersion? current = AppVersion.tryParse(installed);
  if (current == null || rules.storeUrl.trim().isEmpty) return UpdateKind.none;
  final int? build = int.tryParse(installedBuild.trim());

  if (isOlderThan(
    version: current,
    build: build,
    ruleVersion: rules.min,
    ruleBuild: rules.minBuild,
  )) {
    return UpdateKind.required;
  }
  if (!isOlderThan(
    version: current,
    build: build,
    ruleVersion: rules.latest,
    ruleBuild: rules.latestBuild,
  )) {
    return UpdateKind.none;
  }
  if (rules.force) return UpdateKind.required;
  final bool recently =
      lastPrompted != null && now.difference(lastPrompted).abs() < remindAfter;
  return recently ? UpdateKind.none : UpdateKind.optional;
}
