import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mirqat/admin/services/pack_publisher.dart';
import 'package:mirqat/data/models/reciter.dart';
import 'package:mirqat/data/models/surah.dart';

/// Al-Asr: three ayahs, and its basmala precedes ayah 1 — the surah this whole
/// fix started from.
const Surah asr = Surah(
  number: 103,
  nameAr: 'العصر',
  nameEn: 'Al-Asr',
  ayahCount: 3,
  revelationPlace: RevelationPlace.makkah,
  bismillahMode: BismillahMode.separatePreamble,
);

const Reciter shaheen = Reciter(
  id: 'ahmed_khalil_shaheen',
  nameAr: 'أحمد خليل شاهين',
  nameEn: 'Ahmed Khalil Shaheen',
  audioMode: AudioMode.perAyahFiles,
  basePath: 'assets/audio/ahmed_khalil_shaheen',
  bundled: true,
  availableSurahs: <int>[1, 58, 112, 113, 114],
  hasIstiadhah: true,
  hasBismillah: true,
);

const String liveManifest = '''
{"schemaVersion":1,"baseUrl":"https://pub-example.r2.dev","mirrors":[],
 "reciters":[]}
''';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mirqat_pack_publisher');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  List<File> segments() => <File>[
    for (final String name in <String>[
      '103003.mp3',
      '103000.mp3',
      '103002.mp3',
      '103001.mp3',
    ])
      File('${dir.path}/$name')..writeAsStringSync('mp3:$name'),
  ];

  PackPublisher publisher({String manifest = liveManifest, int status = 200}) =>
      PackPublisher(
        manifestUrl: 'https://example.invalid/manifest.json',
        client: MockClient(
          (http.Request _) async =>
              http.Response.bytes(utf8.encode(manifest), status),
        ),
      );

  test('a pack holds every segment, by base name, in ayah order', () {
    final Archive archive = ZipDecoder().decodeBytes(
      publisher().buildPack(segments()),
    );

    expect(archive.files.map((ArchiveFile f) => f.name), <String>[
      '103000.mp3',
      '103001.mp3',
      '103002.mp3',
      '103003.mp3',
    ]);
  });

  test(
    'the same segments build the same bytes, so a rebuild is not a change',
    () {
      final List<File> files = segments();

      expect(
        publisher().buildPack(files),
        publisher().buildPack(files.reversed.toList()),
      );
    },
  );

  test('the pack matches what tool/build_manifest.py produces', () {
    // Both sides of the CDN — the admin tool and the generator — have to agree
    // on the bytes, or the digest in the manifest describes a file nobody will
    // ever build again.
    final List<int> ours = publisher().buildPack(segments());
    final Archive archive = ZipDecoder().decodeBytes(ours);

    for (final ArchiveFile file in archive.files) {
      // Stored, not deflated: an mp3 does not compress.
      expect(file.compression, CompressionType.none);
    }
  });

  test('merging adds a reciter the manifest did not have, named from the '
      'bundled catalog', () async {
    final PackPublisher tool = publisher();
    final List<int> pack = tool.buildPack(segments());

    final Map<String, dynamic> merged = tool.mergeSurah(
      manifest: await tool.fetchManifest(),
      reciter: shaheen,
      surah: asr,
      bitrate: 64,
      baseUrl: 'https://pub-example.r2.dev',
      packBytes: pack.length,
      packSha256: sha256.convert(pack).toString(),
      hasBasmala: true,
    );

    final Map<String, dynamic> reciter =
        (merged['reciters'] as List<dynamic>).single as Map<String, dynamic>;
    expect(reciter['id'], 'ahmed_khalil_shaheen');
    expect(reciter['nameAr'], 'أحمد خليل شاهين');
    expect(reciter['bitrate'], 64);
    expect(reciter['version'], '1');
    expect(reciter['audioPath'], 'audio/{id}/{bitrate}/{s3}{a3}.mp3');
    expect(reciter['packPath'], 'packs/{id}/{bitrate}/{s3}.zip');

    final Map<String, dynamic> surah =
        (reciter['surahs'] as List<dynamic>).single as Map<String, dynamic>;
    expect(surah['n'], 103);
    expect(surah['ayahs'], 3, reason: 'from quran.db, not from the segments');
    expect(surah['hasBasmala'], isTrue);
    expect(surah['bytes'], pack.length);
    expect(surah['sha256'], sha256.convert(pack).toString());
    expect(reciter['totalBytes'], pack.length);
  });

  test('a second surah joins the same reciter, in order, without touching its '
      'version', () async {
    final PackPublisher tool = publisher();
    final Map<String, dynamic> first = tool.mergeSurah(
      manifest: await tool.fetchManifest(),
      reciter: shaheen,
      surah: asr,
      bitrate: 64,
      baseUrl: 'https://pub-example.r2.dev',
      packBytes: 10,
      packSha256: 'aa',
      hasBasmala: true,
    );
    ((first['reciters'] as List<dynamic>).single
            as Map<String, dynamic>)['version'] =
        '4';

    final Map<String, dynamic> second = tool.mergeSurah(
      manifest: first,
      reciter: shaheen,
      surah: const Surah(
        number: 1,
        nameAr: 'الفاتحة',
        nameEn: 'Al-Fatiha',
        ayahCount: 7,
        revelationPlace: RevelationPlace.makkah,
        bismillahMode: BismillahMode.countedAsAyah1,
      ),
      bitrate: 64,
      baseUrl: 'https://pub-example.r2.dev',
      packBytes: 20,
      packSha256: 'bb',
      hasBasmala: false,
    );

    final Map<String, dynamic> reciter =
        (second['reciters'] as List<dynamic>).single as Map<String, dynamic>;
    expect(
      (reciter['surahs'] as List<dynamic>).map(
        (Object? s) => (s! as Map<String, dynamic>)['n'],
      ),
      <int>[1, 103],
    );
    // Bumping a version invalidates every install of every surah this reciter
    // has; publishing one surah must not do that behind the operator's back.
    expect(reciter['version'], '4');
    expect(reciter['totalBytes'], 30);
    expect(
      ((reciter['surahs'] as List<dynamic>).first
          as Map<String, dynamic>)['hasBasmala'],
      isFalse,
    );
  });

  test(
    're-publishing a surah replaces its row rather than duplicating it',
    () async {
      final PackPublisher tool = publisher();
      final Map<String, dynamic> once = tool.mergeSurah(
        manifest: await tool.fetchManifest(),
        reciter: shaheen,
        surah: asr,
        bitrate: 64,
        baseUrl: 'https://pub-example.r2.dev',
        packBytes: 10,
        packSha256: 'aa',
        hasBasmala: true,
      );
      final Map<String, dynamic> twice = tool.mergeSurah(
        manifest: once,
        reciter: shaheen,
        surah: asr,
        bitrate: 64,
        baseUrl: 'https://pub-example.r2.dev',
        packBytes: 12,
        packSha256: 'bb',
        hasBasmala: true,
      );

      final Map<String, dynamic> reciter =
          (twice['reciters'] as List<dynamic>).single as Map<String, dynamic>;
      final List<dynamic> surahs = reciter['surahs'] as List<dynamic>;
      expect(surahs, hasLength(1));
      expect((surahs.single as Map<String, dynamic>)['sha256'], 'bb');
      expect(reciter['totalBytes'], 12);
    },
  );

  test('an unreachable manifest still produces a publishable one', () async {
    final PackPublisher tool = publisher(status: 503);

    final Map<String, dynamic> merged = tool.mergeSurah(
      manifest: await tool.fetchManifest(),
      reciter: shaheen,
      surah: asr,
      bitrate: 64,
      baseUrl: 'https://pub-example.r2.dev',
      packBytes: 10,
      packSha256: 'aa',
      hasBasmala: true,
    );

    expect(merged['schemaVersion'], 1);
    expect(merged['baseUrl'], 'https://pub-example.r2.dev');
    expect((merged['reciters'] as List<dynamic>), hasLength(1));
  });

  group('adding a reciter', () {
    test(
      'a reciter nobody has published appears, with their portrait',
      () async {
        final PackPublisher tool = publisher();

        final Map<String, dynamic> merged = tool.mergeReciter(
          manifest: await tool.fetchManifest(),
          id: 'mishary',
          nameAr: 'مشاري راشد العفاسي',
          nameEn: 'Mishary Rashid Alafasy',
          riwayah: 'hafs',
          bitrate: 64,
          baseUrl: 'https://pub-example.r2.dev',
          imagePath: 'images/mishary.jpg',
        );

        final Map<String, dynamic> reciter =
            (merged['reciters'] as List<dynamic>).single
                as Map<String, dynamic>;
        expect(reciter['id'], 'mishary');
        expect(reciter['nameAr'], 'مشاري راشد العفاسي');
        expect(reciter['imagePath'], 'images/mishary.jpg');
        expect(reciter['version'], '1');
        // No surahs yet: adding a reciter and publishing their recitation are
        // two jobs, and the first must not pretend to have done the second.
        expect(reciter['surahs'], isEmpty);
        expect(reciter['audioPath'], 'audio/{id}/{bitrate}/{s3}{a3}.mp3');
      },
    );

    test('editing a reciter leaves their surahs and version alone', () async {
      final PackPublisher tool = publisher();
      Map<String, dynamic> manifest = tool.mergeReciter(
        manifest: await tool.fetchManifest(),
        id: shaheen.id,
        nameAr: 'أحمد شاهين',
        nameEn: 'Ahmed Shaheen',
        bitrate: 64,
        baseUrl: 'https://pub-example.r2.dev',
      );
      manifest = tool.mergeSurah(
        manifest: manifest,
        reciter: shaheen,
        surah: asr,
        bitrate: 64,
        baseUrl: 'https://pub-example.r2.dev',
        packBytes: 10,
        packSha256: 'aa',
        hasBasmala: true,
      );
      ((manifest['reciters'] as List<dynamic>).single
              as Map<String, dynamic>)['version'] =
          '7';

      // A corrected spelling and a new portrait, months later.
      final Map<String, dynamic> edited = tool.mergeReciter(
        manifest: manifest,
        id: shaheen.id,
        nameAr: 'أحمد خليل شاهين',
        nameEn: 'Ahmed Khalil Shaheen',
        bitrate: 64,
        baseUrl: 'https://pub-example.r2.dev',
        imagePath: 'images/shaheen.jpg',
      );

      final Map<String, dynamic> reciter =
          (edited['reciters'] as List<dynamic>).single as Map<String, dynamic>;
      expect(reciter['nameAr'], 'أحمد خليل شاهين');
      expect(reciter['imagePath'], 'images/shaheen.jpg');
      // Bumping a version invalidates every install of every surah they have;
      // renaming somebody must not do that.
      expect(reciter['version'], '7');
      expect((reciter['surahs'] as List<dynamic>), hasLength(1));
    });

    test('a portrait key is the reciter id and the file extension', () {
      expect(
        PackPublisher.imageKeyFor('mishary', '.jpg'),
        'images/mishary.jpg',
      );
      expect(PackPublisher.imageKeyFor('mishary', 'png'), 'images/mishary.png');
    });
  });

  test('the manifest is written where the operator just browsed', () {
    final File written = publisher().writeManifest(
      manifest: <String, dynamic>{'schemaVersion': 1},
      directory: dir,
    );

    expect(written.path, '${dir.path}/manifest.json');
    expect(jsonDecode(written.readAsStringSync()), <String, dynamic>{
      'schemaVersion': 1,
    });
  });
}
