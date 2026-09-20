import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/bootstrap.dart';
import 'package:mirqat/features/update/cubit/update_cubit.dart';
import 'package:mirqat/features/update/widgets/update_gate.dart';

/// The gate is built on the app's first frame, under the splash, while startup
/// is still registering the services its cubit is made from. On a device that
/// order is real; under the UI harness everything is registered before the
/// first pump, which is how reading the cubit too early got as far as an
/// emulator before anyone saw it.
void main() {
  tearDown(AppBootstrap.reset);

  testWidgets('does not ask for its cubit until startup has finished', (
    WidgetTester tester,
  ) async {
    final Completer<void> startup = Completer<void>();
    AppBootstrap.overrideWith(startup.future);
    int created = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<UpdateCubit>(
          lazy: true,
          create: (_) {
            created++;
            // What the locator does when asked too early.
            throw StateError('UpdateCubit is not registered yet.');
          },
          child: const UpdateGate(child: Text('the app')),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(created, 0);
    expect(find.text('the app'), findsOneWidget);
  });

  testWidgets('a startup that failed leaves the app as it is', (
    WidgetTester tester,
  ) async {
    final Completer<void> startup = Completer<void>();
    AppBootstrap.overrideWith(startup.future);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<UpdateCubit>(
          lazy: true,
          create: (_) => throw StateError('never asked for'),
          child: const UpdateGate(child: Text('the app')),
        ),
      ),
    );
    startup.completeError(StateError('storage would not open'));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('the app'), findsOneWidget);
  });
}
