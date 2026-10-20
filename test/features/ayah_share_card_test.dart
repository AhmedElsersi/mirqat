import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/widgets/ayah_text.dart';
import 'package:mirqat/core/widgets/islamic_frame.dart';
import 'package:mirqat/data/models/ayah.dart';
import 'package:mirqat/features/mushaf/widgets/ayah_share_dialog.dart';

/// The shared card is the full frame whatever the ayah's length: a short
/// ayah once shrank the frame to the width of its words, pushed to one side,
/// with the ayah's plaque hanging off its edge.
void main() {
  Future<void> pump(WidgetTester tester, String text) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          home: Scaffold(
            body: Center(
              // As the dialog shows it: laid out unconstrained, then scaled.
              child: FittedBox(
                child: AyahShareCard(
                  ayah: Ayah(surahNumber: 1, number: 1, text: text),
                  surahName: 'الفاتحة',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The frame's own painting — its band and border — as laid out.
  Rect paintedFrame(WidgetTester tester) => tester.getRect(
    find
        .descendant(
          of: find.byType(IslamicFrame),
          matching: find.byType(CustomPaint),
        )
        .first,
  );

  Rect frameBox(WidgetTester tester) =>
      tester.getRect(find.byType(IslamicFrame));

  for (final (String name, String text) in <(String, String)>[
    ('a short ayah', 'قصيرة'),
    ('a long ayah', List<String>.filled(60, 'كلمة').join(' ')),
  ]) {
    testWidgets('$name fills the whole frame, its words centred in it', (
      WidgetTester tester,
    ) async {
      await pump(tester, text);
      expect(tester.takeException(), isNull);

      final Rect frame = frameBox(tester);
      final Rect painted = paintedFrame(tester);
      expect(painted.width, closeTo(frame.width, 0.5));
      expect(painted.left, closeTo(frame.left, 0.5));

      final Rect words = tester.getRect(
        find
            .descendant(
              of: find.byType(AyahText),
              matching: find.byType(RichText),
            )
            .first,
      );
      expect(words.center.dx, closeTo(frame.center.dx, 1));
    });
  }
}
