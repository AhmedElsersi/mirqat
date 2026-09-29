import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mirqat/admin/cubit/app_info_editor_cubit.dart';
import 'package:mirqat/admin/screen/app_info_editor_screen.dart';
import 'package:mirqat/admin/services/admin_file_picker.dart';
import 'package:mirqat/admin/services/pages_publisher.dart';
import 'package:mirqat/admin/services/r2_client.dart';
import 'package:mirqat/data/datasources/asset_reader.dart';

import 'app_info_editor_test.dart' show config, good;

class _Unused implements AssetReader {
  @override
  Future<String> loadString(String path) async => '{}';
}

class _NoPicker implements AdminFilePicker {
  @override
  Future<String?> pickLinkFile() async => null;

  @override
  Future<String?> pickImage() async => null;

  @override
  Future<String?> pickRecording() async => null;
}

void main() {
  late List<http.Request> puts;

  Future<AppInfoEditorCubit> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    puts = <http.Request>[];
    final AppInfoEditorCubit cubit = AppInfoEditorCubit(
      pagesPublisher: PagesPublisher(
        adminConfig: config,
        client: MockClient((http.Request r) async {
          if (r.method == 'PUT') puts.add(r);
          return http.Response(
            jsonEncode(<String, dynamic>{
              'sha': 'old',
              'commit': <String, String>{'sha': 'abc123'},
            }),
            200,
          );
        }),
      ),
      r2Client: R2Client(adminConfig: config),
      assetReader: _Unused(),
      filePicker: _NoPicker(),
      client: MockClient(
        (_) async =>
            http.Response.bytes(utf8.encode(jsonEncode(good.toJson())), 200),
      ),
    );
    addTearDown(cubit.close);
    await tester.runAsync(cubit.load);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<AppInfoEditorCubit>.value(
          value: cubit,
          child: const AppInfoEditorScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return cubit;
  }

  FilledButton publishButton(WidgetTester tester) =>
      tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Publish app.json'),
          matching: find.byWidgetPredicate((Widget w) => w is FilledButton),
        ),
      );

  testWidgets('opens on what is live, with nothing to publish yet', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Loaded from the Pages site'), findsOneWidget);
    expect(find.text('Our goal'), findsWidgets);
    expect(find.text('Updates'), findsOneWidget);
    expect(publishButton(tester).onPressed, isNull);
    expect(find.text('Nothing changed.'), findsOneWidget);
  });

  testWidgets('an edit can be published; a problem shows and blocks it', (
    WidgetTester tester,
  ) async {
    final AppInfoEditorCubit cubit = await pump(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'English').first,
      'A new about',
    );
    await tester.pump();
    expect(cubit.state.draft.about.en, 'A new about');
    expect(publishButton(tester).onPressed, isNotNull);

    await tester.enterText(find.widgetWithText(TextField, 'English').first, '');
    await tester.pump();
    expect(find.textContaining('About us has no English'), findsOneWidget);
    expect(publishButton(tester).onPressed, isNull);
  });

  testWidgets('raising a minimum asks for it to be typed before it can go', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    final Finder min = find.widgetWithText(
      TextField,
      'Minimum version (blocks below it)',
    );
    await tester.ensureVisible(min.first);
    await tester.enterText(min.first, '1.1.0');
    await tester.pump();

    expect(find.textContaining('Type 1.1.0 to confirm'), findsOneWidget);
    expect(publishButton(tester).onPressed, isNull);

    await tester.enterText(find.widgetWithText(TextField, 'Confirm'), '1.1.0');
    await tester.pump();
    expect(publishButton(tester).onPressed, isNotNull);

    await tester.runAsync(() async {
      await tester.tap(find.text('Publish app.json'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(puts, hasLength(1));
    expect(find.textContaining('Published (abc123)'), findsOneWidget);
  });

  testWidgets('the maintenance platform chips toggle the draft', (
    WidgetTester tester,
  ) async {
    final AppInfoEditorCubit cubit = await pump(tester);
    final Finder ios = find.widgetWithText(FilterChip, 'iOS');
    await tester.ensureVisible(ios);
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(ios).selected, isFalse);

    await tester.tap(ios);
    await tester.pumpAndSettle();
    expect(cubit.state.draft.maintenance.platforms, <String>{'ios'});
    expect(tester.widget<FilterChip>(ios).selected, isTrue);

    await tester.tap(ios);
    await tester.pumpAndSettle();
    expect(cubit.state.draft.maintenance.platforms, isEmpty);
    expect(tester.widget<FilterChip>(ios).selected, isFalse);
  });
}
