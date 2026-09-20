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

/// Which versions one platform's store is on.
class PlatformUpdate extends Equatable {
  const PlatformUpdate({this.min = '', this.latest = '', this.storeUrl = ''});

  static const PlatformUpdate none = PlatformUpdate();

  factory PlatformUpdate.fromJson(Object? json) => json is Map<String, dynamic>
      ? PlatformUpdate(
          min: _text(json['min']),
          latest: _text(json['latest']),
          storeUrl: _text(json['storeUrl']),
        )
      : none;

  /// The oldest version still allowed to run. Below it, the app asks to be
  /// updated and does nothing else. Blank: every version is welcome.
  final String min;

  /// The newest version in the store. Below it, the app mentions the update
  /// and can be told "later". Blank: nothing to mention.
  final String latest;

  /// The store page the update button opens.
  final String storeUrl;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'min': min,
    'latest': latest,
    'storeUrl': storeUrl,
  };

  @override
  List<Object?> get props => <Object?>[min, latest, storeUrl];
}

/// The update rules, one set per store, and an optional word on what is new.
class UpdateRules extends Equatable {
  const UpdateRules({
    this.android = PlatformUpdate.none,
    this.ios = PlatformUpdate.none,
    this.notes = LocalizedText.empty,
  });

  static const UpdateRules none = UpdateRules();

  factory UpdateRules.fromJson(Object? json) => json is Map<String, dynamic>
      ? UpdateRules(
          android: PlatformUpdate.fromJson(json['android']),
          ios: PlatformUpdate.fromJson(json['ios']),
          notes: LocalizedText.fromJson(json['notes']),
        )
      : none;

  final PlatformUpdate android;
  final PlatformUpdate ios;

  /// "What's new", shown under the fixed wording of the prompt. Optional.
  final LocalizedText notes;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'android': android.toJson(),
    'ios': ios.toJson(),
    'notes': notes.toJson(),
  };

  @override
  List<Object?> get props => <Object?>[android, ios, notes];
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
  });

  static const AppInfo empty = AppInfo();

  factory AppInfo.fromJson(Map<String, dynamic> json) => AppInfo(
    about: LocalizedText.fromJson(json['about']),
    goal: LocalizedText.fromJson(json['goal']),
    developer: DeveloperInfo.fromJson(json['developer']),
    update: UpdateRules.fromJson(json['update']),
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

  /// The file as it is published. [schemaVersion] leads, so that a future
  /// build can tell a shape it does not know from one it does.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': schemaVersion,
    'about': about.toJson(),
    'goal': goal.toJson(),
    'developer': developer.toJson(),
    'update': update.toJson(),
  };

  static const int schemaVersion = 1;

  AppInfo copyWith({
    LocalizedText? about,
    LocalizedText? goal,
    DeveloperInfo? developer,
    UpdateRules? update,
  }) => AppInfo(
    about: about ?? this.about,
    goal: goal ?? this.goal,
    developer: developer ?? this.developer,
    update: update ?? this.update,
  );

  @override
  List<Object?> get props => <Object?>[about, goal, developer, update];
}

String _text(Object? value) => value is String ? value.trim() : '';
