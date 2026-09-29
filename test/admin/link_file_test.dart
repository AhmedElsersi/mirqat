import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/admin/services/link_file.dart';

/// A QUL-shaped export over [entries] of (surah, ayah, url).
String export(List<(int, int, String)> entries) => jsonEncode(<String, Object?>{
  for (final (int s, int a, String url) in entries)
    '$s:$a': <String, Object?>{
      'surah_number': s,
      'ayah_number': a,
      'audio_url': url,
      'duration': null,
      'segments': <Object?>[],
    },
});

String host(int s, int a) =>
    'https://audio.invalid/quran/minshawy/'
    '${s.toString().padLeft(3, '0')}${a.toString().padLeft(3, '0')}.mp3';

void main() {
  test('a file whose addresses all fit one template is reduced to it, with '
      'the ayahs listed by surah', () {
    final LinkFile file = LinkFile.parse(
      export(<(int, int, String)>[
        (1, 1, host(1, 1)),
        (1, 2, host(1, 2)),
        (2, 1, host(2, 1)),
        (114, 6, host(114, 6)),
      ]),
    );

    expect(file.template, 'https://audio.invalid/quran/minshawy/{s3}{a3}.mp3');
    expect(file.surahs, <int>[1, 2, 114]);
    expect(file.ayahs[1], <int>{1, 2});
    expect(file.ayahs[114], <int>{6});
    expect(file.ayahCount, 4);
    expect(file.urlFor(114, 6), host(114, 6));
  });

  test('an ayah 0 the file names is kept as a basmala listing, not counted as '
      'an ayah', () {
    final LinkFile file = LinkFile.parse(
      export(<(int, int, String)>[(2, 0, host(2, 0)), (2, 1, host(2, 1))]),
    );
    expect(file.ayahs[2], <int>{0, 1});
    expect(file.ayahCount, 1);
  });

  test('an address that does not fit the template is named, and the file '
      'refused whole', () {
    expect(
      () => LinkFile.parse(
        export(<(int, int, String)>[
          (1, 1, host(1, 1)),
          (1, 2, 'https://audio.invalid/quran/other/001002.mp3'),
          (1, 3, host(1, 3)),
        ]),
      ),
      throwsA(
        isA<LinkFileException>().having(
          (LinkFileException e) => e.problems.join('\n'),
          'problems',
          allOf(
            contains('1 address(es) do not fit the template'),
            contains('1:2 is https://audio.invalid/quran/other/001002.mp3'),
          ),
        ),
      ),
    );
  });

  test('a first address without its surah and ayah as six digits gives no '
      'template', () {
    expect(
      () => LinkFile.parse(
        export(<(int, int, String)>[(1, 1, 'https://audio.invalid/a/b.mp3')]),
      ),
      throwsA(
        isA<LinkFileException>().having(
          (LinkFileException e) => e.problems.single,
          'problem',
          contains('does not contain its surah and ayah as six digits'),
        ),
      ),
    );
  });

  test('the template is read off the last six digits, so a host path with '
      'digits in it is not mistaken for the ayah', () {
    final LinkFile file = LinkFile.parse(
      export(<(int, int, String)>[
        (1, 1, 'https://cdn.invalid/001001/set/001001.mp3'),
        (1, 2, 'https://cdn.invalid/001001/set/001002.mp3'),
      ]),
    );
    expect(file.template, 'https://cdn.invalid/001001/set/{s3}{a3}.mp3');
  });

  test('what is not a file of links at all', () {
    expect(
      () => LinkFile.parse('not json'),
      throwsA(
        isA<LinkFileException>().having(
          (LinkFileException e) => e.problems.single,
          'problem',
          contains('not JSON'),
        ),
      ),
    );
    expect(
      () => LinkFile.parse('[1, 2]'),
      throwsA(
        isA<LinkFileException>().having(
          (LinkFileException e) => e.problems.single,
          'problem',
          contains('not an object'),
        ),
      ),
    );
    expect(
      () => LinkFile.parse(
        '{"1:1": {"surah_number": 1, "ayah_number": 2, "audio_url": "https://x/001001.mp3"}}',
      ),
      throwsA(
        isA<LinkFileException>().having(
          (LinkFileException e) => e.problems.single,
          'problem',
          '"1:1" says it is 1:2.',
        ),
      ),
    );
    expect(
      () => LinkFile.parse(
        '{"1:1": {"surah_number": 1, "ayah_number": 1, "audio_url": "http://x/001001.mp3"}}',
      ),
      throwsA(
        isA<LinkFileException>().having(
          (LinkFileException e) => e.problems.single,
          'problem',
          contains('no https audio_url'),
        ),
      ),
    );
  });
}
