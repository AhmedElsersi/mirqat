import '../../data/models/app_info.dart';

/// What is wrong with an `app.json` before it is published. Empty: nothing.
///
/// The app reads this file forgivingly — a bad field is an empty field, a bad
/// rule is no rule — so nothing here can crash a phone. What these checks
/// guard is *meaning*: a link that goes nowhere, a page with one language
/// missing, and above all an update rule that does not say what its author
/// thinks it says.
List<String> validateAppInfo(AppInfo info) => <String>[
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
  ];
}

/// The platforms whose minimum [draft] raises over [published] — the one edit
/// that locks people out, and so the one that is confirmed by typing.
///
/// Raised means: there was no minimum and now there is, or it is now higher.
/// Lowering or clearing one only ever lets more people in.
Map<String, String> raisedMinimums(AppInfo published, AppInfo draft) {
  final Map<String, String> raised = <String, String>{};
  void check(String name, PlatformUpdate before, PlatformUpdate after) {
    final AppVersion? now = AppVersion.tryParse(after.min);
    if (now == null) return;
    final AppVersion? was = AppVersion.tryParse(before.min);
    if (was == null || was < now) raised[name] = '$now';
  }

  check('Android', published.update.android, draft.update.android);
  check('iOS', published.update.ios, draft.update.ios);
  return raised;
}

/// What an operator has to type to publish [raised]: the versions
/// themselves, in order, separated by a space.
String confirmationFor(Map<String, String> raised) => raised.values.join(' ');
