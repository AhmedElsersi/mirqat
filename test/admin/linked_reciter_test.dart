import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mirqat/admin/config/admin_config.dart';
import 'package:mirqat/admin/cubit/linked_reciter_cubit.dart';
import 'package:mirqat/admin/services/admin_file_picker.dart';
import 'package:mirqat/admin/services/ffmpeg_runner.dart';
import 'package:mirqat/admin/services/pack_publisher.dart';
import 'package:mirqat/admin/services/pages_publisher.dart';
import 'package:mirqat/admin/services/r2_client.dart';
import 'package:path/path.dart' as p;

import '../quran_db_fixtures.dart';

const AdminConfig config = AdminConfig(
  accountId: 'acc',
  accessKey: 'key',
  secretKey: 'secret',
  bucket: 'iqra-audio',
  endpoint: 'https://acc.r2.cloudflarestorage.com',
  publicBase: 'https://pub-example.r2.dev',
  bitrate: 64,
  githubToken: 'ghp_example',
  githubRepo: 'someone/iqra-cdn',
);

const String kHost = 'https://audio.invalid/m/';
const String kManifest = 'https://pages.invalid/manifest.json';

/// The live manifest: one reciter published with packs, one already linked.
const String liveManifest = '''
{"schemaVersion":1,"baseUrl":"https://pub-live.r2.dev","mirrors":[],"reciters":[
 {"id":"packed","nameAr":"ب","nameEn":"Packed","bitrate":64,"version":"2",
  "audioPath":"audio/{id}/{bitrate}/{s3}{a3}.mp3","packPath":"packs/{id}/{bitrate}/{s3}.zip",
  "totalBytes":0,"surahs":[{"n":1,"ayahs":3,"bytes":1,"sha256":"x"}]},
 {"id":"links_old","nameAr":"ق","nameEn":"Old Links","riwayah":"hafs","bitrate":96,
  "version":"3","audioPath":"https://old.invalid/{s3}{a3}.mp3",
  "imagePath":"images/links_old-abc.jpg","totalBytes":0,
  "surahs":[{"n":2,"ayahs":3,"hasBasmala":false}]}]}
''';

String pad3(int n) => n.toString().padLeft(3, '0');
String clipName(int s, int a) => '${pad3(s)}${pad3(a)}.mp3';

/// A QUL-shaped export listing [ayahs] per surah on [kHost].
String exportFor(Map<int, List<int>> ayahs, {String host = kHost}) =>
    jsonEncode(<String, Object?>{
      for (final MapEntry<int, List<int>> e in ayahs.entries)
        for (final int a in e.value)
          '${e.key}:$a': <String, Object?>{
            'surah_number': e.key,
            'ayah_number': a,
            'audio_url': '$host${clipName(e.key, a)}',
          },
    });

const Map<int, List<int>> complete = <int, List<int>>{
  1: <int>[1, 2, 3],
  2: <int>[1, 2, 3],
  3: <int>[1, 2, 3],
};

/// What the host holds by default: every ayah of the three surahs, and a
/// basmala for surah 3 only.
final Set<String> defaultHostFiles = <String>{
  for (final MapEntry<int, List<int>> e in complete.entries)
    for (final int a in e.value) clipName(e.key, a),
  clipName(3, 0),
};

/// The cubit is driven through `useFile`, so the panel only ever hands back a
/// portrait here.
class _Picker implements AdminFilePicker {
  _Picker({this.image});

  final String? image;

  @override
  Future<String?> pickLinkFile() async => null;

  @override
  Future<String?> pickImage() async => image;

  @override
  Future<String?> pickRecording() async => null;
}

/// ffprobe answers every clip is two seconds long.
FfmpegRunner fakeFfmpeg() => FfmpegRunner(
  run: (String executable, List<String> args) async =>
      ProcessResult(0, 0, executable == 'ffprobe' ? '2.0' : '', ''),
);

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('mirqat_links'));
  tearDown(() => temp.deleteSync(recursive: true));

  File write(String name, String contents) =>
      File(p.join(temp.path, name))..writeAsStringSync(contents);

  /// The cubit over a fake network: the live manifest, the host, GitHub and
  /// R2 all answered by [client].
  ({LinkedReciterCubit cubit, List<http.Request> sent, File bundled}) harness({
    Set<String>? hostFiles,
    String manifest = liveManifest,
    String? image,
  }) {
    final Set<String> files = hostFiles ?? defaultHostFiles;
    final List<http.Request> sent = <http.Request>[];
    final MockClient client = MockClient((http.Request request) async {
      sent.add(request);
      final String url = request.url.toString();
      if (url == kManifest) {
        if (!manifest.trimLeft().startsWith('{')) {
          return http.Response(manifest, 503);
        }
        // As Pages serves it: UTF-8, which a plain string response is not.
        return http.Response.bytes(
          utf8.encode(manifest),
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      }
      if (url.startsWith(kHost)) {
        final String name = p.basename(request.url.path);
        if (!files.contains(name)) return http.Response('', 404);
        return request.method == 'HEAD'
            ? http.Response('', 200)
            // 32 000 bytes over two seconds: 128 kbps.
            : http.Response.bytes(List<int>.filled(32000, 0xFF), 200);
      }
      if (request.url.host == 'api.github.com') {
        return request.method == 'GET'
            ? http.Response(jsonEncode(<String, String>{'sha': 'abc'}), 200)
            : http.Response(
                jsonEncode(<String, Object?>{
                  'commit': <String, String>{'sha': 'deadbeef'},
                }),
                200,
              );
      }
      if (request.url.host.endsWith('r2.cloudflarestorage.com')) {
        return http.Response('', request.method == 'HEAD' ? 404 : 200);
      }
      return http.Response('unexpected $url', 500);
    });
    final File bundled = File(p.join(temp.path, 'bundled', 'manifest.json'))
      ..parent.createSync(recursive: true);
    final LinkedReciterCubit cubit = LinkedReciterCubit(
      pagesPublisher: PagesPublisher(adminConfig: config, client: client),
      packPublisher: PackPublisher(client: client, manifestUrl: kManifest),
      r2Client: R2Client(adminConfig: config, client: client),
      filePicker: _Picker(image: image),
      quranRepository: fixtureRepository(),
      ffmpegRunner: fakeFfmpeg(),
      adminConfig: config,
      client: client,
      bundledCopy: bundled,
    );
    addTearDown(cubit.close);
    return (cubit: cubit, sent: sent, bundled: bundled);
  }

  /// Loaded, with the complete file chosen and the reciter named.
  Future<LinkedReciterCubit> ready({
    Set<String>? hostFiles,
    Map<int, List<int>> ayahs = complete,
    String id = 'links_new',
  }) async {
    final LinkedReciterCubit cubit = harness(hostFiles: hostFiles).cubit;
    await cubit.load();
    await cubit.useFile(write('export.json', exportFor(ayahs)).path);
    cubit.edit(
      (LinkedReciterDraft d) => d.copyWith(
        id: id,
        nameAr: 'محمد',
        nameEn: 'Muhammad',
        attributionAr: 'عبر مكتبة',
        attributionEn: 'Via a library',
        riwayah: 'حفص',
      ),
    );
    return cubit;
  }

  test('load reads the live manifest, and a file is laid against the '
      'catalog', () async {
    final LinkedReciterCubit cubit = harness().cubit;
    await cubit.load();
    expect(cubit.state.manifestLive, isTrue);
    expect(cubit.state.manifest['baseUrl'], 'https://pub-live.r2.dev');

    await cubit.useFile(write('export.json', exportFor(complete)).path);
    final LinkedReciterState s = cubit.state;
    expect(s.file?.template, '$kHost{s3}{a3}.mp3');
    expect(s.plan.map((SurahPlan x) => x.number), <int>[1, 2, 3]);
    expect(s.plan.every((SurahPlan x) => x.complete), isTrue);
    expect(s.plan[0].separate, isFalse);
    expect(s.plan[1].separate, isTrue);
    expect(s.message, contains('9 ayahs across 3 surah(s)'));
    expect(s.problems, contains(startsWith('Probe the host')));
    expect(s.row, isNull);
  });

  test('the probe decides which surahs the host has and whether each has a '
      'basmala, and measures the bitrate', () async {
    final LinkedReciterCubit cubit = await ready();
    await cubit.probe();

    final LinkedReciterState s = cubit.state;
    expect(s.probed, isTrue);
    expect(s.probing, isFalse);
    expect(s.plan[0].probe, ProbeOutcome.ok);
    expect(s.plan[0].basmala, isNull, reason: 'first_ayah: nothing to ask');
    expect(s.plan[1].basmala, isFalse, reason: 'no 002000 on the host');
    expect(s.plan[2].basmala, isTrue, reason: '003000 is there');
    expect(s.measuredBitrate, 128);
    expect(s.draft.bitrate, 128);
    expect(s.publishable.map((SurahPlan x) => x.number), <int>[1, 2, 3]);
    expect(s.problems, isEmpty);
  });

  test('the entry: no packPath, the template as audioPath, hasBasmala only '
      'where a surah has a basmala of its own', () async {
    final LinkedReciterCubit cubit = await ready();
    await cubit.probe();

    final Map<String, dynamic> row = cubit.state.row!;
    expect(row.containsKey('packPath'), isFalse);
    expect(row['audioPath'], '$kHost{s3}{a3}.mp3');
    expect(row['id'], 'links_new');
    expect(row['nameAr'], 'محمد');
    expect(row['bitrate'], 128);
    expect(row['version'], '1');
    expect(row['attribution'], <String, String>{
      'ar': 'عبر مكتبة',
      'en': 'Via a library',
    });
    expect(row['surahs'], <Map<String, Object?>>[
      <String, Object?>{'n': 1, 'ayahs': 3},
      <String, Object?>{'n': 2, 'ayahs': 3, 'hasBasmala': false},
      <String, Object?>{'n': 3, 'ayahs': 3, 'hasBasmala': true},
    ]);
    expect(jsonDecode(cubit.json), row);
  });

  test('publish merges the entry into the live manifest, keeps the bucket '
      'address, and writes the bundled copy', () async {
    final harnessed = harness();
    final LinkedReciterCubit cubit = harnessed.cubit;
    await cubit.load();
    await cubit.useFile(write('export.json', exportFor(complete)).path);
    cubit.edit(
      (LinkedReciterDraft d) =>
          d.copyWith(id: 'links_new', nameAr: 'محمد', nameEn: 'Muhammad'),
    );
    await cubit.probe();
    await cubit.publish();

    expect(cubit.state.error, isNull);
    expect(cubit.state.message, contains('Published (deadbeef)'));

    final http.Request put = harnessed.sent.singleWhere(
      (http.Request r) => r.method == 'PUT' && r.url.host == 'api.github.com',
    );
    expect(put.url.path, endsWith('/contents/${config.manifestPath}'));
    final Map<String, dynamic> body =
        jsonDecode(put.body) as Map<String, dynamic>;
    expect(body['message'], contains('links_new'));
    final Map<String, dynamic> published =
        jsonDecode(utf8.decode(base64Decode(body['content'] as String)))
            as Map<String, dynamic>;
    expect(published['baseUrl'], 'https://pub-live.r2.dev');
    final List<dynamic> reciters = published['reciters'] as List<dynamic>;
    expect(
      reciters.map((dynamic r) => (r as Map<String, dynamic>)['id']),
      <String>['links_new', 'links_old', 'packed'],
    );
    expect(reciters[0], cubit.state.row);
    expect(
      (reciters[2] as Map<String, dynamic>)['packPath'],
      'packs/{id}/{bitrate}/{s3}.zip',
      reason: 'the packed reciter is untouched',
    );

    expect(harnessed.bundled.existsSync(), isTrue);
    expect(jsonDecode(harnessed.bundled.readAsStringSync()), published);
    expect(cubit.state.manifest, published);
  });

  test('a surah the host does not have is left out, with a warning', () async {
    final LinkedReciterCubit cubit = await ready(
      hostFiles: defaultHostFiles.difference(<String>{clipName(3, 1)}),
    );
    await cubit.probe();

    expect(cubit.state.plan[2].probe, ProbeOutcome.notFound);
    expect(cubit.state.publishable.map((SurahPlan x) => x.number), <int>[1, 2]);
    expect(cubit.state.warnings, contains(contains('not on the host')));
    expect(cubit.state.problems, isEmpty);
  });

  test('a surah incomplete in the file is never offered, and says what is '
      'missing', () async {
    final LinkedReciterCubit cubit = await ready(
      ayahs: <int, List<int>>{
        1: <int>[1, 2, 3],
        2: <int>[1, 2, 3, 4],
        3: <int>[1, 2],
      },
    );
    expect(cubit.state.plan[1].extra, <int>[4]);
    expect(cubit.state.plan[2].missing, <int>[3]);
    expect(
      cubit.state.warnings,
      containsAll(<Matcher>[
        contains('Surah 2 is incomplete in the file (extra ayah 4)'),
        contains('Surah 3 is incomplete in the file (missing ayah 3)'),
      ]),
    );

    await cubit.probe();
    expect(cubit.state.publishable.map((SurahPlan x) => x.number), <int>[1]);
  });

  test('an id that belongs to a reciter published with packs is refused, and '
      'nothing is sent', () async {
    final harnessed = harness();
    final LinkedReciterCubit cubit = harnessed.cubit;
    await cubit.load();
    await cubit.useFile(write('export.json', exportFor(complete)).path);
    cubit.edit(
      (LinkedReciterDraft d) =>
          d.copyWith(id: 'packed', nameAr: 'ب', nameEn: 'B', bitrate: 64),
    );
    await cubit.probe();

    expect(cubit.state.problems, contains(contains('published with packs')));
    await cubit.publish();
    expect(cubit.state.error, contains('Not published'));
    expect(
      harnessed.sent.where((http.Request r) => r.method == 'PUT'),
      isEmpty,
    );
  });

  test('an id already linked adopts that entry, so re-publishing is a matter '
      'of choosing the file', () async {
    final LinkedReciterCubit cubit = harness().cubit;
    await cubit.load();
    cubit.edit((LinkedReciterDraft d) => d.copyWith(id: 'links_old'));

    final LinkedReciterDraft d = cubit.state.draft;
    expect(d.nameAr, 'ق');
    expect(d.nameEn, 'Old Links');
    expect(d.riwayah, 'hafs');
    expect(d.version, '3');
    expect(d.bitrate, 96);
    expect(d.imagePath, 'images/links_old-abc.jpg');
    expect(d.attributionAr, isEmpty);
    await cubit.useFile(write('export.json', exportFor(complete)).path);
    expect(
      cubit.state.warnings,
      contains(contains('already in the manifest; publishing replaces')),
    );
  });

  test('a file that does not fit one template is refused, and the previous '
      'choice kept', () async {
    final LinkedReciterCubit cubit = await ready();
    final String bad = exportFor(<int, List<int>>{
      1: <int>[1, 2],
    }).replaceFirst('${kHost}001002.mp3', 'https://other.invalid/001002.mp3');
    await cubit.useFile(write('bad.json', bad).path);

    expect(cubit.state.error, contains('do not fit the template'));
    expect(cubit.state.file?.surahs, <int>[1, 2, 3]);
  });

  test('a portrait is uploaded under a name made from its bytes, beside the '
      'id', () async {
    final File image = File(p.join(temp.path, 'face.jpg'))
      ..writeAsBytesSync(utf8.encode('jpegbytes'));
    final harnessed = harness(image: image.path);
    final LinkedReciterCubit cubit = harnessed.cubit;
    await cubit.load();
    cubit.edit((LinkedReciterDraft d) => d.copyWith(id: 'links_new'));
    await cubit.choosePortrait();

    final String expected =
        'images/links_new-'
        '${sha256.convert(utf8.encode('jpegbytes')).toString().substring(0, 12)}'
        '.jpg';
    expect(cubit.state.error, isNull);
    expect(cubit.state.draft.imagePath, expected);
    expect(
      harnessed.sent.any(
        (http.Request r) => r.method == 'PUT' && r.url.path.endsWith(expected),
      ),
      isTrue,
    );
  });

  test('without an id there is nowhere to name a portrait after', () async {
    final LinkedReciterCubit cubit = harness(image: '/nowhere.jpg').cubit;
    await cubit.load();
    await cubit.choosePortrait();
    expect(cubit.state.error, contains('id first'));
  });

  test('a live manifest that could not be read refuses the publish outright: '
      'merging into nothing would drop every other reciter', () async {
    // The site answers with an error page, so fetchManifest hands back the
    // empty manifest.
    final harnessed = harness(manifest: 'Service unavailable');
    final LinkedReciterCubit cubit = harnessed.cubit;
    await cubit.load();
    expect(cubit.state.manifestLive, isFalse);
    expect(cubit.state.error, contains('could not be read'));

    await cubit.useFile(write('export.json', exportFor(complete)).path);
    cubit.edit(
      (LinkedReciterDraft d) =>
          d.copyWith(id: 'links_new', nameAr: 'محمد', nameEn: 'Muhammad'),
    );
    await cubit.probe();

    expect(
      cubit.state.problems,
      contains(contains('drop every other reciter')),
    );
    expect(cubit.state.row, isNull);
    await cubit.publish();
    expect(cubit.state.error, contains('Not published'));
    expect(
      harnessed.sent.where(
        (http.Request r) => r.method == 'PUT' && r.url.host == 'api.github.com',
      ),
      isEmpty,
    );
  });
}
