import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/di/injection.dart';
import 'package:mirqat/data/datasources/asset_reader.dart';
import 'package:mirqat/data/repositories/settings_repository.dart';
import 'package:mirqat/features/settings/screen/settings_screen.dart';
import 'package:mirqat/features/surah_list/widgets/surah_row.dart';
import 'package:mirqat/features/update/cubit/update_cubit.dart';
import 'package:mirqat/services/app_info_service.dart';
import 'package:mirqat/services/app_version_service.dart';
import 'package:mirqat/services/link_opener.dart';

import '../app_harness.dart';

class _Fixed implements AssetReader {
  const _Fixed(this.contents);

  final String contents;

  @override
  Future<String> loadString(String path) async => contents;
}

class _Links implements LinkOpener {
  final List<Uri> opened = <Uri>[];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return true;
  }
}

const String kStore = 'https://play.google.com/store/apps/details?id=x';

void main() {
  late AppHarness harness;
  late _Links links;

  setUp(() async {
    harness = await AppHarness.start();
    links = _Links();
    sl.unregister<LinkOpener>();
    sl.registerLazySingleton<LinkOpener>(() => links);
  });
  tearDown(() async => harness.stop());
  tearDownAll(AppHarness.disposeAll);

  /// The harness's app is version [installedVersion], on Android.
  void publish({String min = '', String latest = '', String notes = ''}) {
    sl.unregister<AppInfoService>();
    sl.registerLazySingleton<AppInfoService>(
      () => offlineAppInfo(
        _Fixed(
          jsonEncode(<String, dynamic>{
            'schemaVersion': 1,
            'update': <String, dynamic>{
              'android': <String, String>{
                'min': min,
                'latest': latest,
                'storeUrl': kStore,
              },
              'notes': <String, String>{'ar': notes, 'en': notes},
            },
          }),
        ),
      ),
      dispose: (AppInfoService s) => s.dispose(),
    );
    sl.unregister<UpdateCubit>();
    sl.registerFactory<UpdateCubit>(
      () => UpdateCubit(
        appInfoService: sl<AppInfoService>(),
        appVersionService: sl<AppVersionService>(),
        platformOverride: TargetPlatform.android,
      ),
    );
  }

  testWidgets('with nothing published the app opens as it always did', (
    WidgetTester tester,
  ) async {
    publish();
    await harness.pumpApp(tester);
    expect(find.text('تحديث'), findsNothing);
    expect(find.byType(SurahRow), findsWidgets);
  });

  testWidgets('a newer version is mentioned, with what is new, and "later" '
      'is a day\'s quiet that outlives the app', (WidgetTester tester) async {
    publish(latest: '9.0.0', notes: 'سور جديدة');
    await harness.pumpApp(tester);

    expect(find.text('يتوفّر إصدار أحدث'), findsOneWidget);
    expect(find.text('سور جديدة'), findsOneWidget);

    await AppHarness.tapAndSettle(tester, find.text('لاحقًا'));
    expect(find.text('يتوفّر إصدار أحدث'), findsNothing);
    expect(find.byType(SurahRow).hitTestable(), findsWidgets);

    // Written down, so that the next launch — today — keeps quiet too.
    final DateTime? at = await tester.runAsync<DateTime?>(
      () async => (await sl<SettingsRepository>().read()).fold<DateTime?>(
        (_) => null,
        (s) => s.updatePromptedAt,
      ),
    );
    expect(at, isNotNull);

    await harness.pumpApp(tester);
    expect(find.text('يتوفّر إصدار أحدث'), findsNothing);
  });

  testWidgets('the update button goes to this platform\'s store page', (
    WidgetTester tester,
  ) async {
    publish(latest: '9.0.0');
    await harness.pumpApp(tester);

    await AppHarness.tapAndSettle(tester, find.text('تحديث'));
    expect(links.opened.single, Uri.parse(kStore));
  });

  testWidgets('while it is up, the app underneath takes no taps', (
    WidgetTester tester,
  ) async {
    publish(latest: '9.0.0');
    await harness.pumpApp(tester);
    expect(find.byType(SurahRow).hitTestable(), findsNothing);
  });

  testWidgets('below the minimum there is one button and no way past it', (
    WidgetTester tester,
  ) async {
    publish(min: '9.0.0', latest: '9.0.0');
    await harness.pumpApp(tester);

    expect(find.text('يلزم تحديث التطبيق'), findsOneWidget);
    expect(find.text('لاحقًا'), findsNothing);
    expect(find.byType(SurahRow).hitTestable(), findsNothing);

    // Back cannot put it away: it is not a route, so there is nothing of it
    // to pop.
    await tester.binding.handlePopRoute();
    await AppHarness.settle(tester);
    expect(find.text('يلزم تحديث التطبيق'), findsOneWidget);

    await AppHarness.tapAndSettle(tester, find.text('تحديث'));
    expect(links.opened.single, Uri.parse(kStore));
    expect(find.text('يلزم تحديث التطبيق'), findsOneWidget);
  });

  testWidgets('Settings ends with the version that is running', (
    WidgetTester tester,
  ) async {
    await harness.pumpApp(tester);
    await AppHarness.tapAndSettle(tester, find.byIcon(Icons.settings_outlined));
    expect(find.byType(SettingsScreen), findsOneWidget);

    final Finder version = find.textContaining(installedVersion);
    await tester.scrollUntilVisible(
      version,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(version, findsOneWidget);
    expect(find.textContaining('الإصدار'), findsOneWidget);
  });
}
