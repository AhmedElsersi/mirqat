import '../../data/models/app_info.dart';

/// What is wrong with an `app.json` before it is published. Empty: nothing.
///
/// The app reads this file forgivingly — a bad field is an empty field, a bad
/// rule is no rule — so nothing here can crash a phone. What these checks
/// guard is *meaning*: a link that goes nowhere, a page with one language
/// missing, and above all an update rule that does not say what its author
/// thinks it says.
List<String> validateAppInfo(AppInfo info, {DateTime? now}) => <String>[
  ..._bothLanguages('About us', info.about),
  ..._bothLanguages('Our goal', info.goal),
  if (info.developer.name.isEmpty) 'The developer has no name.',
  for (final DeveloperLink link in info.developer.links.keys)
    if (info.developer.uriFor(link) == null)
      'The developer\'s ${link.name} — "${info.developer.links[link]}" — is '
          'not something a phone can open.',
  if (info.developer.photo.isNotEmpty &&
      Uri.tryParse(info.developer.photo) == null)
    'The developer\'s photo is not an address.',
  ..._platform('Android', info.update.android),
  ..._platform('iOS', info.update.ios),
  if (info.update.notes.ar.trim().isEmpty !=
      info.update.notes.en.trim().isEmpty)
    '"What is new" is written in one language only. Whoever reads the other '
        'would see it in the wrong one.',
  ..._maintenance(info.maintenance, now ?? DateTime.now()),
];

List<String> _maintenance(Maintenance sign, DateTime now) => <String>[
  if (sign.enabled) ...<String>[
    ..._bothLanguages('The maintenance message', sign.message),
    if (sign.title.ar.trim().isEmpty != sign.title.en.trim().isEmpty)
      'The maintenance title is written in one language only.',
    if (sign.until != null && !now.isBefore(sign.until!))
      'Maintenance is on, but its "until" (${sign.until!.toUtc().toIso8601String()}) '
          'has already passed, so the app would ignore it. Clear it, or set '
          'a time to come.',
  ],
];

List<String> _bothLanguages(String what, LocalizedText text) => <String>[
  if (text.ar.trim().isEmpty) '$what has no Arabic text.',
  if (text.en.trim().isEmpty) '$what has no English text.',
];

List<String> _platform(String name, PlatformUpdate rules) {
  final AppVersion? min = AppVersion.tryParse(rules.min);
  final AppVersion? latest = AppVersion.tryParse(rules.latest);
  final bool hasRule = rules.min.isNotEmpty || rules.latest.isNotEmpty;
  final Uri? store = Uri.tryParse(rules.storeUrl);

  return <String>[
    if (rules.min.isNotEmpty && min == null)
      '$name: the minimum version "${rules.min}" is not a version. The app '
          'would ignore it.',
    if (rules.latest.isNotEmpty && latest == null)
      '$name: the latest version "${rules.latest}" is not a version. The app '
          'would ignore it.',
    // Everyone below `min` is told they must update to something they would
    // then be told is still too old.
    if (min != null && latest != null && latest < min)
      '$name: the minimum ($min) is newer than the latest ($latest).',
    if (min != null && latest == null)
      '$name: a minimum with no latest. Say which version the store is on, so '
          'that a build ahead of it is recognisably ahead.',
    if (hasRule &&
        (store == null || store.scheme != 'https' || store.host.isEmpty))
      '$name: there is a rule but no https store page. The app shows no '
          'prompt without one — a prompt whose button goes nowhere is a '
          'dead end.',
    if (rules.minBuild != null && min == null)
      '$name: a minimum build with no minimum version. A build number only '
          'tells two uploads of one version apart.',
    if (rules.latestBuild != null && latest == null)
      '$name: a latest build with no latest version.',
    if (min != null &&
        latest != null &&
        min.compareTo(latest) == 0 &&
        rules.minBuild != null &&
        rules.latestBuild != null &&
        rules.latestBuild! < rules.minBuild!)
      '$name: the minimum build (${rules.minBuild}) is above the latest '
          'build (${rules.latestBuild}) of the same version.',
    if (rules.force && latest == null)
      '$name: "force" is on but there is no latest version, so there is '
          'nothing to force.',
  ];
}

/// What in [draft] locks people out that [published] did not — the edits
/// that are confirmed by typing, because a slip in any of them locks out
/// everyone.
///
/// A minimum raised (no minimum before, a higher version now, or a higher
/// build of the same version); a forced latest switched on, or raised while
/// on; and the maintenance sign put up, or widened to more platforms.
/// Lowering, clearing or taking down only ever lets more people in, and
/// needs nothing.
Map<String, String> raisedMinimums(AppInfo published, AppInfo draft) {
  final Map<String, String> raised = <String, String>{};

  bool higher(
    String wasVersion,
    int? wasBuild,
    String nowVersion,
    int? nowBuild,
  ) {
    final AppVersion? now = AppVersion.tryParse(nowVersion);
    if (now == null) return false;
    final AppVersion? was = AppVersion.tryParse(wasVersion);
    if (was == null || was < now) return true;
    if (now < was) return false;
    return nowBuild != null && (wasBuild == null || wasBuild < nowBuild);
  }

  String label(String version, int? build) =>
      build == null ? version : '$version+$build';

  void check(String name, PlatformUpdate before, PlatformUpdate after) {
    if (higher(before.min, before.minBuild, after.min, after.minBuild)) {
      raised[name] = label('${AppVersion.tryParse(after.min)}', after.minBuild);
    }
    final bool forcedNow =
        after.force && AppVersion.tryParse(after.latest) != null;
    final bool forcedBefore =
        before.force && AppVersion.tryParse(before.latest) != null;
    if (forcedNow &&
        (!forcedBefore ||
            higher(
              before.latest,
              before.latestBuild,
              after.latest,
              after.latestBuild,
            ))) {
      raised['$name forced update'] =
          'force-${name.toLowerCase()}-${label('${AppVersion.tryParse(after.latest)}', after.latestBuild)}';
    }
  }

  check('Android', published.update.android, draft.update.android);
  check('iOS', published.update.ios, draft.update.ios);

  final Maintenance was = published.maintenance;
  final Maintenance now = draft.maintenance;
  final Set<String> wasFor = was.enabled
      ? (was.platforms.isEmpty ? Maintenance.knownPlatforms : was.platforms)
      : const <String>{};
  final Set<String> nowFor = now.enabled
      ? (now.platforms.isEmpty ? Maintenance.knownPlatforms : now.platforms)
      : const <String>{};
  if (nowFor.difference(wasFor).isNotEmpty) {
    raised['Maintenance'] = 'maintenance';
  }
  return raised;
}

/// What an operator has to type to publish [raised]: the values themselves,
/// in order, separated by a space — a version, `1.2.0+25` for a build,
/// `force-android-1.2.0` for a forced update, `maintenance` for the sign.
String confirmationFor(Map<String, String> raised) => raised.values.join(' ');
