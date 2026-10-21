import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/data/models/mutashabihat.dart';
import 'package:mirqat/domain/entities/ayah_ref.dart';

/// QUL's phrases.json shape (its documented format), over ayahs of the real
/// quran.db. The ranges lie inside each ayah's recited words.
Map<String, Object?> source({Map<String, Object?> extra = const {}}) =>
    <String, Object?>{
      // "… وَلَا خَوۡفٌ عَلَيۡهِمۡ وَلَا هُمۡ يَحۡزَنُونَ" closing three ayahs.
      '7': <String, Object?>{
        'surahs': 2,
        'ayahs': 3,
        'count': 3,
        'source': <String, Object?>{'key': '2:62', 'from': 19, 'to': 24},
        'ayah': <String, Object?>{
          '2:62': <List<int>>[
            <int>[19, 24],
          ],
          '2:112': <List<int>>[
            <int>[12, 17],
          ],
          '5:69': <List<int>>[
            <int>[15, 20],
          ],
        },
      },
      // In one ayah only: nothing is shared.
      '8': <String, Object?>{
        'ayah': <String, Object?>{
          '2:23': <List<int>>[
            <int>[15, 17],
          ],
        },
      },
      ...extra,
    };

void main() {
  final bool hasPython =
      Process.runSync('which', <String>['python3']).exitCode == 0;

  group(
    'tool/build_mutashabihat.py',
    skip: hasPython ? null : 'python3 is not on PATH',
    () {
      late Directory dir;
      late File out;

      setUp(() {
        dir = Directory.systemTemp.createTempSync('mutashabihat_tool');
        out = File('${dir.path}/mutashabihat.json');
      });
      tearDown(() => dir.deleteSync(recursive: true));

      ProcessResult run(String input, [List<String> args = const <String>[]]) =>
          Process.runSync('python3', <String>[
            '-I',
            'tool/build_mutashabihat.py',
            input,
            '--out',
            out.path,
            ...args,
          ]);

      File write(Map<String, Object?> json) =>
          File('${dir.path}/phrases.json')..writeAsStringSync(jsonEncode(json));

      test('turns QUL\'s phrases into references the app reads', () {
        final ProcessResult r = run(write(source()).path);
        expect(r.exitCode, 0, reason: '${r.stderr}');

        final MutashabihatIndex index = MutashabihatIndex.fromJson(
          jsonDecode(out.readAsStringSync()),
        );
        expect(index.hasSimilar(const AyahRef(2, 112)), isTrue);
        expect(
          index.similarTo(const AyahRef(2, 62)).map((SimilarAyah s) => s.ref),
          <AyahRef>[const AyahRef(2, 112), const AyahRef(5, 69)],
        );
        expect(
          index.hasSimilar(const AyahRef(2, 23)),
          isFalse,
          reason: 'a phrase in one ayah is shared with nothing',
        );
        expect(out.readAsStringSync(), isNot(contains('خَوۡفٌ')));
      });

      test('reads the zip QUL serves, and rebuilds byte-identical', () {
        final Archive zip = Archive()
          ..addFile(
            ArchiveFile.string(
              'mutashabihat/phrases.json',
              jsonEncode(source()),
            ),
          )
          ..addFile(
            ArchiveFile.string('mutashabihat/phrase_verses.json', '{}'),
          );
        final File z = File('${dir.path}/m.zip')
          ..writeAsBytesSync(ZipEncoder().encode(zip));
        expect(run(z.path).exitCode, 0);
        final String first = out.readAsStringSync();
        expect(run(z.path).exitCode, 0);
        expect(out.readAsStringSync(), first);
      });

      test('a range outside its ayah refuses the whole source, and writes '
          'nothing', () {
        final ProcessResult r = run(
          write(
            source(
              extra: <String, Object?>{
                '9': <String, Object?>{
                  'ayah': <String, Object?>{
                    '2:112': <List<int>>[
                      <int>[16, 40],
                    ],
                    '2:62': <List<int>>[
                      <int>[1, 2],
                    ],
                  },
                },
              },
            ),
          ).path,
        );
        expect(r.exitCode, isNot(0));
        expect('${r.stderr}', contains('2:112'));
        expect(out.existsSync(), isFalse);
      });

      test('an ayah the text does not have refuses the source', () {
        final ProcessResult r = run(
          write(
            source(
              extra: <String, Object?>{
                '9': <String, Object?>{
                  'ayah': <String, Object?>{
                    '1:9': <List<int>>[
                      <int>[1, 2],
                    ],
                    '2:62': <List<int>>[
                      <int>[1, 2],
                    ],
                  },
                },
              },
            ),
          ).path,
        );
        expect(r.exitCode, isNot(0));
        expect('${r.stderr}', contains('1:9'));
      });

      group('--leave-out', () {
        // The shape of resource 73's one known error: a range running past
        // the end of its ayah (2:112 has 17 recited words).
        Map<String, Object?> withBadReference() => source(
          extra: <String, Object?>{
            '9': <String, Object?>{
              'ayah': <String, Object?>{
                '2:112': <List<int>>[
                  <int>[16, 19],
                ],
                '2:62': <List<int>>[
                  <int>[23, 24],
                ],
                '5:69': <List<int>>[
                  <int>[19, 20],
                ],
              },
            },
          },
        );

        test(
          'drops the one reference named, and keeps the phrase\'s others',
          () {
            final ProcessResult r = run(
              write(withBadReference()).path,
              <String>['--leave-out', '9:2:112'],
            );
            expect(r.exitCode, 0, reason: '${r.stderr}');
            expect(
              '${r.stdout}',
              contains('left out by hand: phrase 9 in 2:112'),
            );
            final Map<String, dynamic> json =
                jsonDecode(out.readAsStringSync()) as Map<String, dynamic>;
            final Map<String, dynamic> nine = (json['phrases'] as List<dynamic>)
                .cast<Map<String, dynamic>>()
                .singleWhere((Map<String, dynamic> p) => p['id'] == 9);
            expect(nine['ayahs'], <List<int>>[
              <int>[2, 62, 23, 24],
              <int>[5, 69, 19, 20],
            ]);
          },
        );

        test('naming a reference the source does not have refuses the build, '
            'so a leave-out cannot outlive its error', () {
          final ProcessResult r = run(write(source()).path, <String>[
            '--leave-out',
            '9:2:112',
          ]);
          expect(r.exitCode, isNot(0));
          expect('${r.stderr}', contains('9:2:112'));
          expect(out.existsSync(), isFalse);
        });

        test('is refused when it is not PHRASE:SURAH:AYAH', () {
          final ProcessResult r = run(write(source()).path, <String>[
            '--leave-out',
            '2:112',
          ]);
          expect(r.exitCode, isNot(0));
          expect(out.existsSync(), isFalse);
        });
      });

      test('a phrase in more ayahs than asked for is left out, and said', () {
        final ProcessResult r = run(write(source()).path, <String>[
          '--max-ayahs',
          '2',
        ]);
        expect(r.exitCode, 0);
        expect('${r.stdout}', contains('1 in more than 2 ayahs'));
        final MutashabihatIndex index = MutashabihatIndex.fromJson(
          jsonDecode(out.readAsStringSync()),
        );
        expect(index.isEmpty, isTrue);
      });
    },
  );
}
