/// The admin panel's text size: the scope that scales every label and ayah
/// under it, the ⌘-chords that move it, and the ends it stops at.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/admin/screen/admin_text_scale.dart';

void main() {
  Future<void> pumpScope(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      builder: (BuildContext context, Widget? child) =>
          AdminTextScaleScope(child: child!),
      home: const Scaffold(body: Text('probe')),
    ),
  );

  /// What a 14-point style actually renders at under the scope.
  double sizeOf14(WidgetTester tester) =>
      MediaQuery.textScalerOf(tester.element(find.text('probe'))).scale(14);

  Future<void> chord(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
  }

  testWidgets('until asked, the scope changes nothing', (
    WidgetTester tester,
  ) async {
    await pumpScope(tester);
    expect(sizeOf14(tester), 14);
  });

  testWidgets('⌘+ enlarges, ⌘− shrinks, ⌘0 puts it back', (
    WidgetTester tester,
  ) async {
    await pumpScope(tester);

    await chord(tester, LogicalKeyboardKey.equal);
    expect(sizeOf14(tester), closeTo(15.4, 0.001));

    await chord(tester, LogicalKeyboardKey.minus);
    await chord(tester, LogicalKeyboardKey.minus);
    expect(sizeOf14(tester), closeTo(12.6, 0.001));

    await chord(tester, LogicalKeyboardKey.digit0);
    expect(sizeOf14(tester), 14);
  });

  testWidgets('the size stops at its ends instead of running away', (
    WidgetTester tester,
  ) async {
    await pumpScope(tester);

    for (int i = 0; i < 15; i++) {
      await chord(tester, LogicalKeyboardKey.equal);
    }
    expect(sizeOf14(tester), closeTo(14 * 2.0, 0.001));

    for (int i = 0; i < 20; i++) {
      await chord(tester, LogicalKeyboardKey.minus);
    }
    expect(sizeOf14(tester), closeTo(14 * 0.8, 0.001));
  });

  testWidgets('the system accessibility setting is multiplied, never '
      'written over', (WidgetTester tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpScope(tester);
    expect(sizeOf14(tester), closeTo(14 * 1.5, 0.001));

    await chord(tester, LogicalKeyboardKey.equal);
    expect(sizeOf14(tester), closeTo(14 * 1.5 * 1.1, 0.001));
  });
}
