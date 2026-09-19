import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mirqat/core/di/injection.dart';
import 'package:mirqat/services/audio/audio_storage.dart';
import 'package:mirqat/services/reciter_image_cache.dart';
import 'package:mirqat/core/theme/app_theme.dart';
import 'package:mirqat/core/widgets/reciter_avatar.dart';
import 'package:mirqat/data/models/reciter.dart';

/// A catalogued reciter with [imagePath] set to [imagePath].
Reciter reciterWith(String? imagePath) => Reciter(
  id: 'test_reciter',
  nameAr: 'أحمد خليل شاهين',
  nameEn: 'Ahmed Khalil Shaheen',
  audioMode: AudioMode.perAyahFiles,
  basePath: 'assets/audio/test_reciter',
  bundled: true,
  availableSurahs: const <int>[1],
  hasIstiadhah: false,
  hasBismillah: false,
  imagePath: imagePath,
);

Widget host(Widget child, {Brightness brightness = Brightness.light}) =>
    ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (BuildContext context, Widget? _) => MaterialApp(
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    );

void main() {
  testWidgets('a null imagePath renders the fallback, not a hole', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(ReciterAvatar(reciter: reciterWith(null), diameter: 48)),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // No Image is even attempted.
    expect(find.byType(Image), findsNothing);
    // The initial of the Arabic name stands in.
    expect(find.text('أ'), findsOneWidget);
  });

  testWidgets('a missing asset falls back instead of throwing', (
    WidgetTester tester,
  ) async {
    // The path is well-formed and catalogued, and there is nothing behind it —
    // a reciter whose photo was deleted, or a typo in the catalog. This is the
    // case that shows a red error box if errorBuilder is not wired.
    await tester.pumpWidget(
      host(
        ReciterAvatar(
          reciter: reciterWith('assets/images/reciters/does_not_exist.jpeg'),
          diameter: 48,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('أ'), findsOneWidget);
  });

  testWidgets('corrupt bytes fall back instead of throwing', (
    WidgetTester tester,
  ) async {
    // Declared, present, and not a decodable image.
    const String path = 'assets/data/reciters.json';
    await tester.pumpWidget(
      host(ReciterAvatar(reciter: reciterWith(path), diameter: 48)),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('أ'), findsOneWidget);
  });

  testWidgets('a portrait on the CDN is fetched, cached and drawn', (
    WidgetTester tester,
  ) async {
    // The path that lets a reciter be added without an app release: nothing
    // is bundled for them, and the only picture is the one the manifest names.
    final Directory root = Directory.systemTemp.createTempSync('mirqat_avatar');
    addTearDown(() => root.deleteSync(recursive: true));

    await sl.reset();
    sl.registerLazySingleton<ReciterImageCache>(
      () => ReciterImageCache(
        audioStorage: AudioStorage(resolveStorageDirectory: () async => root),
        client: MockClient(
          (http.Request _) async => http.Response.bytes(onePixelPng, 200),
        ),
      ),
    );
    addTearDown(sl.reset);

    await tester.pumpWidget(
      host(
        ReciterAvatar(
          reciter: reciterWith(
            null,
          ).copyWithImageUrl('https://pub-example.r2.dev/images/mishary.png'),
          diameter: 48,
        ),
      ),
    );
    // The initial stands in until the bytes are there — no spinner.
    expect(find.text('أ'), findsOneWidget);

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('أ'), findsNothing);
    expect(
      Directory('${root.path}/images').listSync(),
      hasLength(1),
      reason: 'kept on disk for the next launch',
    );
  });

  testWidgets('a portrait that cannot be fetched leaves the initial', (
    WidgetTester tester,
  ) async {
    final Directory root = Directory.systemTemp.createTempSync('mirqat_avatar');
    addTearDown(() => root.deleteSync(recursive: true));

    await sl.reset();
    sl.registerLazySingleton<ReciterImageCache>(
      () => ReciterImageCache(
        audioStorage: AudioStorage(resolveStorageDirectory: () async => root),
        client: MockClient((http.Request _) async => http.Response('', 404)),
      ),
    );
    addTearDown(sl.reset);

    await tester.pumpWidget(
      host(
        ReciterAvatar(
          reciter: reciterWith(
            null,
          ).copyWithImageUrl('https://pub-example.r2.dev/images/nobody.png'),
          diameter: 48,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('أ'), findsOneWidget);
  });

  testWidgets('stays inside its diameter at a large text scale', (
    WidgetTester tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      host(ReciterAvatar(reciter: reciterWith(null), diameter: 40)),
    );
    await tester.pumpAndSettle();

    // The fallback glyph is sized off the circle, not the text scale, so a
    // large system font cannot push it out of a fixed-diameter clip.
    expect(tester.takeException(), isNull);
    final Size size = tester.getSize(find.byType(ReciterAvatar));
    expect(size.width, size.height);
    expect(size.width, lessThanOrEqualTo(40 * 1.5));
  });

  testWidgets('renders in both themes without throwing', (
    WidgetTester tester,
  ) async {
    for (final Brightness brightness in Brightness.values) {
      await tester.pumpWidget(
        host(
          ReciterAvatar(reciter: reciterWith(null), diameter: 56),
          brightness: brightness,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$brightness');
    }
  });
}

/// A 1×1 PNG — the smallest thing Flutter will actually decode.
const List<int> onePixelPng = <int>[
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  2,
  0,
  0,
  0,
  144,
  119,
  83,
  222,
  0,
  0,
  0,
  12,
  73,
  68,
  65,
  84,
  120,
  156,
  99,
  80,
  112,
  72,
  0,
  0,
  1,
  68,
  0,
  193,
  11,
  141,
  150,
  66,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
];

extension on Reciter {
  Reciter copyWithImageUrl(String url) => Reciter(
    id: id,
    nameAr: nameAr,
    nameEn: nameEn,
    audioMode: audioMode,
    basePath: basePath,
    bundled: bundled,
    availableSurahs: availableSurahs,
    hasIstiadhah: hasIstiadhah,
    hasBismillah: hasBismillah,
    imagePath: imagePath,
    imageUrl: url,
  );
}
