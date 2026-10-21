import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mirqat/core/constants/asset_paths.dart';
import 'package:mirqat/core/error/exceptions.dart';
import 'package:mirqat/data/datasources/asset_reader.dart';
import 'package:mirqat/services/audio/audio_storage.dart';
import 'package:mirqat/services/audio/manifest_service.dart';
import 'package:mirqat/services/qpc_font_service.dart';

/// A stand-in font: the TrueType magic, then bytes.
final Uint8List font = Uint8List.fromList(<int>[
  0,
  1,
  0,
  0,
  ...List<int>.filled(64, 7),
]);
final Uint8List packed = Uint8List.fromList(const GZipEncoder().encode(font));

const String manifest =
    '{"schemaVersion":1,"baseUrl":"https://cdn.test/root","reciters":[]}';

class _Assets implements AssetReader {
  _Assets(this.list);
  final Map<String, Object?> list;

  @override
  Future<String> loadString(String path) async => switch (path) {
    AssetPaths.qpcV2Fonts => jsonEncode(list),
    AssetPaths.bundledManifest => manifest,
    _ => throw AssetNotFoundException(path, 'absent'),
  };
}

void main() {
  late Directory dir;
  late List<Uri> requested;
  late List<String> registered;
  late Uint8List served;

  Map<String, Object?> listOf(List<int> pages) => <String, Object?>{
    'schemaVersion': 1,
    'path': 'fonts/qpc-v2/p{n3}.ttf.gz',
    'pages': <Map<String, Object?>>[
      for (final int n in pages)
        <String, Object?>{
          'n': n,
          'bytes': packed.length,
          'sha256': sha256.convert(packed).toString(),
        },
    ],
  };

  QpcFontService service({List<int> pages = const <int>[3]}) {
    final _Assets assets = _Assets(listOf(pages));
    final MockClient client = MockClient((http.Request r) async {
      requested.add(r.url);
      return http.Response.bytes(served, 200);
    });
    return QpcFontService(
      assets: assets,
      manifestService: ManifestService(
        assets,
        client: MockClient((_) async => http.Response('', 404)),
        storageDirectory: () async => dir,
      ),
      audioStorage: AudioStorage(resolveStorageDirectory: () async => dir),
      client: client,
      registrar: (String family, Uint8List bytes) async {
        expect(bytes, font, reason: 'the engine is handed the unpacked font');
        registered.add(family);
      },
    );
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('qpc_fonts');
    requested = <Uri>[];
    registered = <String>[];
    served = packed;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('a page font is fetched from beside the audio, checked, kept and '
      'registered; asked again, it is already there', () async {
    final QpcFontService fonts = service();
    expect(await fonts.ensure(3), isTrue);
    expect(
      requested.single.toString(),
      'https://cdn.test/root/fonts/qpc-v2/p003.ttf.gz',
    );
    expect(registered, <String>['QpcV2Page3']);
    expect(fonts.loaded.value, <int>{3});
    expect(File('${dir.path}/fonts/qpc_v2/p003.ttf').readAsBytesSync(), font);

    expect(await fonts.ensure(3), isTrue);
    expect(requested, hasLength(1));
    expect(await fonts.downloadedCount(), 1);

    // A new run reads it from disk, with no request.
    final QpcFontService again = service();
    expect(await again.ensure(3), isTrue);
    expect(requested, hasLength(1));
  });

  test('bytes that are not the published font are refused, and the page is '
      'not asked for again at once', () async {
    served = Uint8List.fromList(<int>[...packed.reversed]);
    final QpcFontService fonts = service();
    expect(await fonts.ensure(3), isFalse);
    expect(registered, isEmpty);
    expect(fonts.loaded.value, isEmpty);
    expect(File('${dir.path}/fonts/qpc_v2/p003.ttf').existsSync(), isFalse);

    served = packed;
    expect(await fonts.ensure(3), isFalse, reason: 'waits before retrying');
    expect(requested, hasLength(1));
  });

  test('a page the list does not name is never fetched', () async {
    final QpcFontService fonts = service();
    expect(await fonts.ensure(9), isFalse);
    expect(requested, isEmpty);
  });

  test('every page at once, with progress; then all removed', () async {
    final QpcFontService fonts = service(pages: <int>[1, 2, 3]);
    final List<int> progress = <int>[];
    expect(
      await fonts.downloadAll(onProgress: (int done, _) => progress.add(done)),
      0,
    );
    expect(progress, <int>[1, 2, 3]);
    expect(await fonts.downloadedCount(), 3);
    expect(registered, isEmpty, reason: 'downloaded, not loaded');
    expect((await fonts.totals()).pages, 3);

    await fonts.deleteAll();
    expect(await fonts.downloadedCount(), 0);
  });
}
