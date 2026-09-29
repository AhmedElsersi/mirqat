import 'dart:convert';

import 'package:equatable/equatable.dart';

/// A piece of prose in both of the app's languages.
class LocalizedText extends Equatable {
  const LocalizedText({this.ar = '', this.en = ''});

  static const LocalizedText empty = LocalizedText();

  factory LocalizedText.fromJson(Object? json) => json is Map<String, dynamic>
      ? LocalizedText(ar: _text(json['ar']), en: _text(json['en']))
      : empty;

  final String ar;
  final String en;

  /// The text for [languageCode], falling back to the other language rather
  /// than to nothing: a paragraph in the wrong language still says what the
  /// app is; a blank page does not.
  String of(String languageCode) {
    final String wanted = languageCode == 'ar' ? ar : en;
    if (wanted.trim().isNotEmpty) return wanted;
    return languageCode == 'ar' ? en : ar;
  }

  bool get isEmpty => ar.trim().isEmpty && en.trim().isEmpty;

  LocalizedText copyWith({String? ar, String? en}) =>
      LocalizedText(ar: ar ?? this.ar, en: en ?? this.en);

  Map<String, dynamic> toJson() => <String, dynamic>{'ar': ar, 'en': en};

  @override
  List<Object?> get props => <Object?>[ar, en];
}

/// The ways to reach the developer. Every one is optional, and an empty one
/// is simply not shown.
enum DeveloperLink { email, github, linkedin, whatsapp, facebook }

class DeveloperInfo extends Equatable {
  const DeveloperInfo({
    this.name = LocalizedText.empty,
    this.photo = '',
    this.links = const <DeveloperLink, String>{},
  });

  static const DeveloperInfo empty = DeveloperInfo();

  factory DeveloperInfo.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return empty;
    return DeveloperInfo(
      name: LocalizedText.fromJson(json['name']),
      photo: _text(json['photo']),
      links: <DeveloperLink, String>{
        for (final DeveloperLink link in DeveloperLink.values)
          if (_text(json[link.name]).isNotEmpty) link: _text(json[link.name]),
      },
    );
  }

  final LocalizedText name;

  /// A URL, or empty for none — the card then shows the name's initial.
  final String photo;

  /// Only the links that were filled in, in the order they are shown.
  final Map<DeveloperLink, String> links;

  /// Where a tap on [link] goes, or null if what was written for it cannot be
  /// turned into an address. Written forgivingly, because these values are
  /// typed by hand into a form: an email with no `mailto:`, a WhatsApp number
  /// with spaces and a plus, a profile with no `https://`.
  Uri? uriFor(DeveloperLink link) {
    final String raw = (links[link] ?? '').trim();
    if (raw.isEmpty) return null;
    switch (link) {
      case DeveloperLink.email:
        final String address = raw.replaceFirst(RegExp('^mailto:'), '');
        return address.contains('@')
            ? Uri(scheme: 'mailto', path: address)
            : null;
      case DeveloperLink.whatsapp:
        if (raw.startsWith('http')) return Uri.tryParse(raw);
        final String digits = raw.replaceAll(RegExp(r'\D'), '');
        return digits.isEmpty ? null : Uri.parse('https://wa.me/$digits');
      case DeveloperLink.github:
      case DeveloperLink.linkedin:
      case DeveloperLink.facebook:
        final Uri? uri = Uri.tryParse(
          raw.contains('://') ? raw : 'https://$raw',
        );
        return uri != null && uri.host.isNotEmpty ? uri : null;
    }
  }

  DeveloperInfo copyWith({
    LocalizedText? name,
    String? photo,
    Map<DeveloperLink, String>? links,
  }) => DeveloperInfo(
    name: name ?? this.name,
    photo: photo ?? this.photo,
    links: links ?? this.links,
  );

  /// With [link] set to [value] — or taken away, when [value] is blank. The
  /// links keep the order they are shown in, whatever order they were set in.
  DeveloperInfo withLink(DeveloperLink link, String value) {
    final Map<DeveloperLink, String> next = <DeveloperLink, String>{...links};
    if (value.trim().isEmpty) {
      next.remove(link);
    } else {
      next[link] = value.trim();
    }
    return copyWith(
      links: <DeveloperLink, String>{
        for (final DeveloperLink l in DeveloperLink.values)
          if (next[l] case final String kept) l: kept,
      },
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name.toJson(),
    'photo': photo,
    for (final DeveloperLink link in DeveloperLink.values)
      link.name: links[link] ?? '',
  };

  @override
  List<Object?> get props => <Object?>[name, photo, links];
}

/// A version as the stores write it: `1.4.0`. Compared number by number, so
/// that 1.10.0 is newer than 1.9.0, which comparing the strings gets wrong.
class AppVersion extends Equatable implements Comparable<AppVersion> {
  const AppVersion(this.parts);

  /// Null for anything that is not dotted numbers — a blank field, a typo.
  /// A build suffix (`+7`) or a pre-release tag (`-beta`) is ignored: the
  /// stores order releases by the numbers before it.
  static AppVersion? tryParse(String? text) {
    final String core = (text ?? '').trim().split(RegExp('[+-]')).first;
    if (core.isEmpty) return null;
    final List<int> parts = <int>[];
    for (final String piece in core.split('.')) {
      final int? n = int.tryParse(piece);
      if (n == null || n < 0) return null;
      parts.add(n);
    }
    return AppVersion(List<int>.unmodifiable(parts));
  }

  final List<int> parts;

  @override
  int compareTo(AppVersion other) {
    final int length = parts.length > other.parts.length
        ? parts.length
        : other.parts.length;
    for (int i = 0; i < length; i++) {
      final int a = i < parts.length ? parts[i] : 0;
      final int b = i < other.parts.length ? other.parts[i] : 0;
      if (a != b) return a - b;
    }
    return 0;
  }

  bool operator <(AppVersion other) => compareTo(other) < 0;

  @override
  List<Object?> get props => <Object?>[parts];

  @override
  String toString() => parts.join('.');
}

/// Which releases one platform's store is on, and how firmly to ask.
///
/// A release is a version *and* a build number, as the stores see it: two
/// uploads of 1.2.0 are builds 24 and 25, and a rule may need to tell them
/// apart. The build number is optional on every rule — a version alone
/// compares by version alone.
class PlatformUpdate extends Equatable {
  const PlatformUpdate({
    this.min = '',
    this.minBuild,
    this.latest = '',
    this.latestBuild,
    this.force = false,
    this.storeUrl = '',
  });

  static const PlatformUpdate none = PlatformUpdate();

  factory PlatformUpdate.fromJson(Object? json) => json is Map<String, dynamic>
      ? PlatformUpdate(
          min: _text(json['min']),
          minBuild: _build(json['minBuild']),
          latest: _text(json['latest']),
          latestBuild: _build(json['latestBuild']),
          force: json['force'] == true,
          storeUrl: _text(json['storeUrl']),
        )
      : none;

  /// The oldest version still allowed to run. Below it, the app asks to be
  /// updated and does nothing else. Blank: every version is welcome.
  final String min;

  /// With [min]: the oldest build of that version still allowed. Null: any
  /// build of [min] is allowed.
  final int? minBuild;

  /// The newest version in the store. Below it, the app mentions the update
  /// and can be told "later" — unless [force]. Blank: nothing to mention.
  final String latest;

  /// With [latest]: the build the store is on. Null: any build of [latest]
  /// counts as current.
  final int? latestBuild;

  /// Whether the latest release is mandatory: everything below it is treated
  /// as below the minimum, and there is no "later". The switch for a release
  /// that fixes something that cannot wait, without moving the minimum.
  final bool force;

  /// The store page the update button opens.
  final String storeUrl;

  /// The release the prompt asks for, as a label: the latest where there is
  /// one, else the minimum, with the build in brackets when it is named.
  String get target {
    final String version = latest.isNotEmpty ? latest : min;
    final int? build = latest.isNotEmpty ? latestBuild : minBuild;
    if (version.isEmpty) return '';
    return build == null ? version : '$version ($build)';
  }

  PlatformUpdate copyWith({
    String? min,
    int? minBuild,
    bool clearMinBuild = false,
    String? latest,
    int? latestBuild,
    bool clearLatestBuild = false,
    bool? force,
    String? storeUrl,
  }) => PlatformUpdate(
    min: min ?? this.min,
    minBuild: clearMinBuild ? null : (minBuild ?? this.minBuild),
    latest: latest ?? this.latest,
    latestBuild: clearLatestBuild ? null : (latestBuild ?? this.latestBuild),
    force: force ?? this.force,
    storeUrl: storeUrl ?? this.storeUrl,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'min': min,
    'minBuild': minBuild,
    'latest': latest,
    'latestBuild': latestBuild,
    'force': force,
    'storeUrl': storeUrl,
  };

  @override
  List<Object?> get props => <Object?>[
    min,
    minBuild,
    latest,
    latestBuild,
    force,
    storeUrl,
  ];
}

/// A build number as it might be written: a number, or digits in a string.
/// Anything else, and a zero or less, is no build number.
int? _build(Object? value) {
  final int? n = switch (value) {
    final int v => v,
    final String v => int.tryParse(v.trim()),
    _ => null,
  };
  return n == null || n <= 0 ? null : n;
}

/// The update rules, one set per store, and an optional word on what is new.
class UpdateRules extends Equatable {
  const UpdateRules({
    this.android = PlatformUpdate.none,
    this.ios = PlatformUpdate.none,
    this.notes = LocalizedText.empty,
    this.remindAfterDays = defaultRemindAfterDays,
  });

  static const UpdateRules none = UpdateRules();

  /// How long "later" holds by default: a day.
  static const int defaultRemindAfterDays = 1;

  factory UpdateRules.fromJson(Object? json) => json is Map<String, dynamic>
      ? UpdateRules(
          android: PlatformUpdate.fromJson(json['android']),
          ios: PlatformUpdate.fromJson(json['ios']),
          notes: LocalizedText.fromJson(json['notes']),
          remindAfterDays:
              _build(json['remindAfterDays']) ?? defaultRemindAfterDays,
        )
      : none;

  final PlatformUpdate android;
  final PlatformUpdate ios;

  /// "What's new", shown under the fixed wording of the prompt. Optional.
  final LocalizedText notes;

  /// How many days "later" buys before an optional update is mentioned
  /// again. Never less than one: a prompt on every launch is nagging.
  final int remindAfterDays;

  PlatformUpdate forPlatform(String platform) => switch (platform) {
    'android' => android,
    'ios' => ios,
    _ => PlatformUpdate.none,
  };

  UpdateRules copyWith({
    PlatformUpdate? android,
    PlatformUpdate? ios,
    LocalizedText? notes,
    int? remindAfterDays,
  }) => UpdateRules(
    android: android ?? this.android,
    ios: ios ?? this.ios,
    notes: notes ?? this.notes,
    remindAfterDays: remindAfterDays ?? this.remindAfterDays,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'android': android.toJson(),
    'ios': ios.toJson(),
    'notes': notes.toJson(),
    'remindAfterDays': remindAfterDays,
  };

  @override
  List<Object?> get props => <Object?>[android, ios, notes, remindAfterDays];
}

/// A closed sign: the app shows a page saying so, with a way to try again,
/// and nothing else, for as long as the sign is up.
///
/// It is the one thing in this file that stops every install at once, and
/// it is read as forgivingly as the rest: a sign whose `until` has passed is
/// down, so a switch nobody remembered to turn off cannot keep people out
/// for good.
class Maintenance extends Equatable {
  const Maintenance({
    this.enabled = false,
    this.title = LocalizedText.empty,
    this.message = LocalizedText.empty,
    this.platforms = const <String>{},
    this.until,
  });

  static const Maintenance off = Maintenance();

  /// The platforms a sign may name. Empty names them all.
  static const Set<String> knownPlatforms = <String>{'android', 'ios'};

  factory Maintenance.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return off;
    final Object? rawPlatforms = json['platforms'];
    return Maintenance(
      enabled: json['enabled'] == true,
      title: LocalizedText.fromJson(json['title']),
      message: LocalizedText.fromJson(json['message']),
      platforms: <String>{
        if (rawPlatforms is List)
          for (final Object? p in rawPlatforms)
            if (p is String && knownPlatforms.contains(p.trim().toLowerCase()))
              p.trim().toLowerCase(),
      },
      until: switch (json['until']) {
        final String s when s.trim().isNotEmpty => DateTime.tryParse(s.trim()),
        _ => null,
      },
    );
  }

  final bool enabled;

  /// The heading and the words on the page. Blank: the app's own wording.
  final LocalizedText title;
  final LocalizedText message;

  /// Which stores the sign is up for. Empty: every platform.
  final Set<String> platforms;

  /// When the sign comes down by itself, if a time was given. Shown on the
  /// page as when to expect the app back.
  final DateTime? until;

  /// Whether the sign is up for [platform] at [now].
  bool isActive({required String platform, required DateTime now}) =>
      enabled &&
      (platforms.isEmpty || platforms.contains(platform)) &&
      (until == null || now.isBefore(until!));

  Maintenance copyWith({
    bool? enabled,
    LocalizedText? title,
    LocalizedText? message,
    Set<String>? platforms,
    DateTime? until,
    bool clearUntil = false,
  }) => Maintenance(
    enabled: enabled ?? this.enabled,
    title: title ?? this.title,
    message: message ?? this.message,
    platforms: platforms ?? this.platforms,
    until: clearUntil ? null : (until ?? this.until),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'enabled': enabled,
    'title': title.toJson(),
    'message': message.toJson(),
    'platforms': platforms.toList()..sort(),
    'until': until?.toUtc().toIso8601String() ?? '',
  };

  @override
  List<Object?> get props => <Object?>[
    enabled,
    title,
    message,
    platforms,
    until,
  ];
}

/// What the app says about itself: `app.json`.
///
/// Read forgivingly. A field that is missing or of the wrong type reads as
/// empty and the screen that wanted it shows nothing there — this file is
/// edited by hand and, from the next stage, fetched over a network, and a
/// typo in it must never be able to take a screen down.
class AppInfo extends Equatable {
  const AppInfo({
    this.about = LocalizedText.empty,
    this.goal = LocalizedText.empty,
    this.developer = DeveloperInfo.empty,
    this.update = UpdateRules.none,
    this.maintenance = Maintenance.off,
  });

  static const AppInfo empty = AppInfo();

  factory AppInfo.fromJson(Map<String, dynamic> json) => AppInfo(
    about: LocalizedText.fromJson(json['about']),
    goal: LocalizedText.fromJson(json['goal']),
    developer: DeveloperInfo.fromJson(json['developer']),
    update: UpdateRules.fromJson(json['update']),
    maintenance: Maintenance.fromJson(json['maintenance']),
  );

  /// Parses [source], or answers [empty] for anything that is not an object.
  factory AppInfo.parse(String source) {
    try {
      final Object? decoded = jsonDecode(source);
      return decoded is Map<String, dynamic>
          ? AppInfo.fromJson(decoded)
          : empty;
    } on FormatException {
      return empty;
    }
  }

  final LocalizedText about;
  final LocalizedText goal;
  final DeveloperInfo developer;
  final UpdateRules update;

  /// The closed sign, up or down.
  final Maintenance maintenance;

  /// The file as it is published. [schemaVersion] leads, so that a future
  /// build can tell a shape it does not know from one it does.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': schemaVersion,
    'about': about.toJson(),
    'goal': goal.toJson(),
    'developer': developer.toJson(),
    'update': update.toJson(),
    'maintenance': maintenance.toJson(),
  };

  static const int schemaVersion = 1;

  AppInfo copyWith({
    LocalizedText? about,
    LocalizedText? goal,
    DeveloperInfo? developer,
    UpdateRules? update,
    Maintenance? maintenance,
  }) => AppInfo(
    about: about ?? this.about,
    goal: goal ?? this.goal,
    developer: developer ?? this.developer,
    update: update ?? this.update,
    maintenance: maintenance ?? this.maintenance,
  );

  @override
  List<Object?> get props => <Object?>[
    about,
    goal,
    developer,
    update,
    maintenance,
  ];
}

String _text(Object? value) => value is String ? value.trim() : '';
