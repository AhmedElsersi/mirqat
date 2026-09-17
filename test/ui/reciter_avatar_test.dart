import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('the real catalogued portrait loads', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(
        ReciterAvatar(
          reciter: reciterWith(
            'assets/images/reciters/ahmed_khalil_shaheen.jpeg',
          ),
          diameter: 48,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(Image), findsOneWidget);
    // The fallback is not also on screen.
    expect(find.text('أ'), findsNothing);
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
