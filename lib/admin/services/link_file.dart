import 'dart:convert';

import 'package:equatable/equatable.dart';

/// A file of links: one audio address per ayah, the way QUL (Quran.com's
/// Quranic Universal Library) exports a recitation someone else cut and hosts.
///
/// ```json
/// { "1:1": { "surah_number": 1, "ayah_number": 1,
///            "audio_url": "https://host/…/001001.mp3", … }, … }
/// ```
///
/// The app never sees this file. What it gets is a manifest entry whose
/// `audioPath` is the one template every address here fits (CLAUDE.md A.5, *a
/// reciter without packs*), so the whole file has to reduce to that template
/// — a file that does not is refused, with the addresses that broke the
/// pattern named. Everything else about the entry is the host's to answer and
/// `quran.db`'s to check, and neither happens here.
class LinkFile extends Equatable {
  const LinkFile({required this.template, required this.ayahs});

  /// The absolute `audioPath` template, with `{s3}{a3}` where the surah and
  /// ayah go.
  final String template;

  /// The ayahs the file lists, by surah. Ayah 0 is a basmala the file itself
  /// names; QUL exports do not, and the host is asked instead.
  final Map<int, Set<int>> ayahs;

  /// Surahs the file has at least one ayah of, ascending.
  List<int> get surahs => ayahs.keys.toList()..sort();

  int get ayahCount => ayahs.values.fold<int>(
    0,
    (int sum, Set<int> s) => sum + s.where((int a) => a > 0).length,
  );

  /// [template] filled in for one ayah. The same substitution the app makes.
  String urlFor(int surah, int ayah) => fill(template, surah, ayah);

  static String fill(String template, int surah, int ayah) =>
      template.replaceAll('{s3}', pad3(surah)).replaceAll('{a3}', pad3(ayah));

  static String pad3(int n) => n.toString().padLeft(3, '0');

  /// Reads [json], or throws [LinkFileException] naming what is wrong with it.
  factory LinkFile.parse(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (e) {
      throw LinkFileException(<String>['The file is not JSON: ${e.message}']);
    }
    if (decoded is! Map<String, dynamic>) {
      throw LinkFileException(<String>[
        'The file is not an object keyed "surah:ayah".',
      ]);
    }

    final List<String> problems = <String>[];
    final List<({int surah, int ayah, String url})> entries =
        <({int surah, int ayah, String url})>[];
    for (final MapEntry<String, dynamic> entry in decoded.entries) {
      final Object? value = entry.value;
      if (value is! Map<String, dynamic>) {
        problems.add('"${entry.key}" is not an object.');
        continue;
      }
      final Object? surah = value['surah_number'];
      final Object? ayah = value['ayah_number'];
      final Object? url = value['audio_url'];
      if (surah is! int || ayah is! int || surah < 1 || ayah < 0) {
        problems.add('"${entry.key}" has no surah_number and ayah_number.');
        continue;
      }
      if (entry.key != '$surah:$ayah') {
        problems.add('"${entry.key}" says it is $surah:$ayah.');
        continue;
      }
      if (url is! String || !url.startsWith('https://')) {
        problems.add('"${entry.key}" has no https audio_url.');
        continue;
      }
      entries.add((surah: surah, ayah: ayah, url: url));
    }
    if (entries.isEmpty && problems.isEmpty) {
      problems.add('The file lists no ayahs.');
    }
    if (problems.isNotEmpty) throw LinkFileException(_capped(problems));

    entries.sort(
      (a, b) => a.surah != b.surah
          ? a.surah.compareTo(b.surah)
          : a.ayah.compareTo(b.ayah),
    );

    // The template is read off the first address: the six digits of its
    // surah and ayah become the placeholders. Then every other address has
    // to be that template filled in, or the file describes more than one
    // layout and the app's one template cannot carry it.
    final ({int surah, int ayah, String url}) first = entries.first;
    final String digits = '${pad3(first.surah)}${pad3(first.ayah)}';
    final int at = first.url.lastIndexOf(digits);
    if (at == -1) {
      throw LinkFileException(<String>[
        'The first address, ${first.url}, does not contain its surah and '
            'ayah as six digits ($digits), so no template can be read off it.',
      ]);
    }
    final String template =
        '${first.url.substring(0, at)}{s3}{a3}${first.url.substring(at + 6)}';

    final List<String> misfits = <String>[];
    final Map<int, Set<int>> ayahs = <int, Set<int>>{};
    for (final ({int surah, int ayah, String url}) e in entries) {
      if (fill(template, e.surah, e.ayah) != e.url) {
        misfits.add('${e.surah}:${e.ayah} is ${e.url}');
        continue;
      }
      ayahs.putIfAbsent(e.surah, () => <int>{}).add(e.ayah);
    }
    if (misfits.isNotEmpty) {
      throw LinkFileException(<String>[
        '${misfits.length} address(es) do not fit the template $template:',
        ..._capped(misfits),
      ]);
    }

    return LinkFile(
      template: template,
      ayahs: Map<int, Set<int>>.unmodifiable(<int, Set<int>>{
        for (final MapEntry<int, Set<int>> e in ayahs.entries)
          e.key: Set<int>.unmodifiable(e.value),
      }),
    );
  }

  static List<String> _capped(List<String> lines, {int keep = 8}) =>
      lines.length <= keep
      ? lines
      : <String>[...lines.take(keep), '… and ${lines.length - keep} more.'];

  @override
  List<Object?> get props => <Object?>[template, ayahs];
}

class LinkFileException implements Exception {
  const LinkFileException(this.problems);

  final List<String> problems;

  @override
  String toString() => problems.join('\n');
}
