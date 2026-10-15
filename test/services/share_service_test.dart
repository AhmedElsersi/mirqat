import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/services/share_service.dart';
import 'package:path/path.dart' as p;

/// ShareService writes the image where the platform's FileProvider can see
/// it and hands the path over the channel. A platform without a handler is a
/// quiet no, never a crash (the toggle pattern of KeepAwakeService).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel('com.mirqat.app/share');

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('mirqat_share'));
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    tmp.deleteSync(recursive: true);
  });

  ShareService service() => ShareService(channel, () async => tmp);

  test('writes the image under share/ and hands its path to the platform, '
      'with the mime type and the caption', () async {
    MethodCall? seen;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          seen = call;
          return null;
        });

    final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3]);
    final bool shared = await service().shareImage(
      bytes,
      filename: 'ayah_1_1.png',
      text: 'caption',
    );

    expect(shared, isTrue);
    expect(seen, isNotNull);
    expect(seen!.method, 'shareFile');
    final Map<Object?, Object?> args = seen!.arguments as Map<Object?, Object?>;
    expect(args['mimeType'], 'image/png');
    expect(args['text'], 'caption');
    final String path = args['path']! as String;
    expect(path, p.join(tmp.path, 'share', 'ayah_1_1.png'));
    expect(File(path).readAsBytesSync(), bytes);
  });

  test('a platform without a handler is a quiet no', () async {
    expect(
      await service().shareImage(
        Uint8List.fromList(<int>[1]),
        filename: 'x.png',
      ),
      isFalse,
    );
  });

  test('a platform error is a quiet no', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (MethodCall call) async =>
              throw PlatformException(code: 'share_failed'),
        );
    expect(
      await service().shareImage(
        Uint8List.fromList(<int>[1]),
        filename: 'x.png',
      ),
      isFalse,
    );
  });
}
