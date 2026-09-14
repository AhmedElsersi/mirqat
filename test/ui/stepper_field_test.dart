import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/theme/app_theme.dart';
import 'package:mirqat/core/widgets/session_controls.dart';

/// Owns the value the way a cubit would, and records every change it is sent.
/// Bounded 1..999, like the repetition count.
class _Host extends StatefulWidget {
  const _Host({required this.initial, this.editable = true, this.formatValue});

  final int initial;
  final bool editable;
  final String Function(int)? formatValue;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late int value = widget.initial;
  final List<int> changes = <int>[];

  @override
  Widget build(BuildContext context) => StepperField(
    value: value,
    min: 1,
    max: 999,
    editable: widget.editable,
    formatValue: widget.formatValue,
    onChanged: (int v) => setState(() {
      value = v;
      changes.add(v);
    }),
  );
}

Future<void> _pumpHost(WidgetTester tester, _Host host) async {
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (BuildContext context, Widget? _) => MaterialApp(
        theme: AppTheme.light,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: Center(child: host)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

_HostState _hostOf(WidgetTester tester) =>
    tester.state<_HostState>(find.byType(_Host));

String fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

/// Western digits written as Arabic-Indic, as `toLocalisedString` does under
/// `ar` — without depending on the locale the test happens to run in.
String arabicIndic(int v) => String.fromCharCodes(
  '$v'.codeUnits.map((int u) => u - 0x30 + 0x660),
);

void main() {
  group('typing', () {
    testWidgets('a typed number is applied as it is typed', (
      WidgetTester tester,
    ) async {
      await _pumpHost(tester, const _Host(initial: 3));

      await tester.enterText(find.byType(TextField), '45');
      await tester.pump();

      expect(_hostOf(tester).value, 45);
    });

    testWidgets('anything but digits is dropped', (WidgetTester tester) async {
      await _pumpHost(tester, const _Host(initial: 3));

      await tester.enterText(find.byType(TextField), '1a-2.');
      await tester.pump();

      expect(fieldText(tester), '12');
      expect(_hostOf(tester).value, 12);
    });

    testWidgets('no more digits than the maximum has', (
      WidgetTester tester,
    ) async {
      await _pumpHost(tester, const _Host(initial: 3));

      await tester.enterText(find.byType(TextField), '12');
      await tester.enterText(find.byType(TextField), '1234');
      await tester.pump();

      expect(fieldText(tester), '12');
      expect(_hostOf(tester).value, 12);
    });

    testWidgets('Arabic-Indic digits are read, and shown in the field\'s own '
        'numerals', (WidgetTester tester) async {
      await _pumpHost(tester, _Host(initial: 3, formatValue: arabicIndic));
      expect(fieldText(tester), '٣');

      // An English keyboard...
      await tester.enterText(find.byType(TextField), '25');
      await tester.pump();
      expect(fieldText(tester), '٢٥');
      expect(_hostOf(tester).value, 25);

      // ...and an Arabic one land in the same place.
      await tester.enterText(find.byType(TextField), '٧٠');
      await tester.pump();
      expect(fieldText(tester), '٧٠');
      expect(_hostOf(tester).value, 70);
    });

    testWidgets('an out-of-range number waits, then settles to the bound '
        'when the field is left', (WidgetTester tester) async {
      await _pumpHost(tester, const _Host(initial: 3));

      await tester.enterText(find.byType(TextField), '0');
      await tester.pump();
      // Not applied while typing: it may be the start of something longer.
      expect(_hostOf(tester).value, 3);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(_hostOf(tester).value, 1);
      expect(fieldText(tester), '1');
    });

    testWidgets('an emptied field goes back to the current value', (
      WidgetTester tester,
    ) async {
      await _pumpHost(tester, const _Host(initial: 7));

      await tester.enterText(find.byType(TextField), '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(_hostOf(tester).value, 7);
      expect(fieldText(tester), '7');
      expect(_hostOf(tester).changes, isEmpty);
    });

    testWidgets('the buttons update the field', (WidgetTester tester) async {
      await _pumpHost(tester, const _Host(initial: 3));

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();

      expect(fieldText(tester), '4');
    });

    testWidgets('without editable the value is plain text', (
      WidgetTester tester,
    ) async {
      await _pumpHost(tester, const _Host(initial: 3, editable: false));

      expect(find.byType(TextField), findsNothing);
      expect(find.text('3'), findsOneWidget);
    });
  });

  group('press and hold', () {
    testWidgets('a tap still steps exactly once', (WidgetTester tester) async {
      await _pumpHost(tester, const _Host(initial: 3));

      await tester.tap(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();

      expect(_hostOf(tester).changes, <int>[2]);
    });

    testWidgets('holding plus keeps counting up until it is released', (
      WidgetTester tester,
    ) async {
      await _pumpHost(tester, const _Host(initial: 3));

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.add)),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 10));
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await gesture.up();
      await tester.pump();

      final int released = _hostOf(tester).value;
      expect(released, greaterThan(10));
      // One step at a time, never skipping.
      expect(_hostOf(tester).changes, <int>[
        for (int v = 4; v <= released; v++) v,
      ]);

      await tester.pump(const Duration(seconds: 2));
      expect(_hostOf(tester).value, released);
    });

    testWidgets('holding minus counts down and stops at the minimum', (
      WidgetTester tester,
    ) async {
      await _pumpHost(tester, const _Host(initial: 4));

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.remove)),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 10));
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(_hostOf(tester).value, 1);
      expect(_hostOf(tester).changes, <int>[3, 2, 1]);

      await gesture.up();
      await tester.pump();
    });
  });
}
