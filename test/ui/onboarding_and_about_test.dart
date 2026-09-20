import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/di/injection.dart';
import 'package:mirqat/core/localization/app_localization.dart';
import 'package:mirqat/data/datasources/asset_reader.dart';
import 'package:mirqat/data/repositories/settings_repository.dart';
import 'package:mirqat/features/about/screen/developer_screen.dart';
import 'package:mirqat/features/about/screen/how_to_use_screen.dart';
import 'package:mirqat/features/onboarding/screen/onboarding_screen.dart';
import 'package:mirqat/features/settings/screen/settings_screen.dart';
import 'package:mirqat/features/surah_list/widgets/surah_row.dart';
import 'package:mirqat/services/app_info_service.dart';
import 'package:mirqat/services/link_opener.dart';

import '../app_harness.dart';

class _Links implements LinkOpener {
  final List<Uri> opened = <Uri>[];
  bool succeed = true;

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return succeed;
  }
}

class _Fixed implements AssetReader {
  const _Fixed(this.contents);

  final String contents;

  @override
  Future<String> loadString(String path) async => contents;
}

void main() {
  late AppHarness harness;

  setUp(() async => harness = await AppHarness.start());
  tearDown(() async => harness.stop());
  tearDownAll(AppHarness.disposeAll);

  Future<bool> seenOnDisk(WidgetTester tester) async => (await tester.runAsync(
    () async => (await sl<SettingsRepository>().read()).fold(
      (_) => false,
      (s) => s.onboardingSeen,
    ),
  ))!;

  group('the introduction', () {
    testWidgets('greets a first launch, and skipping it goes home for good', (
      WidgetTester tester,
    ) async {
      await tester.runAsync(AppHarness.freshInstall);
      await harness.pumpApp(tester);

      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byType(SurahRow), findsNothing);

      await AppHarness.tapAndSettle(tester, find.text('تخطٍّ'));
      expect(find.byType(SurahRow), findsWidgets);
      expect(await seenOnDisk(tester), isTrue);

      // The next launch goes straight home.
      await harness.pumpApp(tester);
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.byType(SurahRow), findsWidgets);
    });

    testWidgets('read to the end, its last button starts the app', (
      WidgetTester tester,
    ) async {
      await tester.runAsync(AppHarness.freshInstall);
      await harness.pumpApp(tester);

      for (int i = 0; i < OnboardingScreen.pages.length - 1; i++) {
        expect(find.text('تخطٍّ').hitTestable(), findsOneWidget);
        await AppHarness.tapAndSettle(tester, find.text('التالي'));
      }
      // The last leaf: nothing left to skip, and the button says so.
      expect(find.text('تخطٍّ').hitTestable(), findsNothing);
      expect(find.text('التالي'), findsNothing);

      await AppHarness.tapAndSettle(tester, find.text('ابدأ'));
      expect(find.byType(SurahRow), findsWidgets);
      expect(await seenOnDisk(tester), isTrue);
    });

    testWidgets('is not shown to someone who has seen it', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      expect(find.byType(OnboardingScreen), findsNothing);
    });

    testWidgets('can be brought up again from How to use, and returns there', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      await AppHarness.tapAndSettle(
        tester,
        find.byIcon(Icons.settings_outlined),
      );
      await tester.scrollUntilVisible(
        find.text('طريقة الاستخدام'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      // Visible is not yet tappable while a row only peeks over the edge.
      await tester.ensureVisible(find.text('طريقة الاستخدام'));
      await tester.pumpAndSettle();
      await AppHarness.tapAndSettle(tester, find.text('طريقة الاستخدام'));
      expect(find.byType(HowToUseScreen), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('عرض المقدّمة مرة أخرى'),
        300,
        // This page's own list: Settings is still mounted underneath, and
        // its list comes first in the tree.
        scrollable: find
            .descendant(
              of: find.byType(HowToUseScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(find.text('عرض المقدّمة مرة أخرى'));
      await tester.pumpAndSettle();
      await AppHarness.tapAndSettle(tester, find.text('عرض المقدّمة مرة أخرى'));
      expect(find.byType(OnboardingScreen), findsOneWidget);

      await AppHarness.tapAndSettle(tester, find.text('تخطٍّ'));
      expect(find.byType(HowToUseScreen), findsOneWidget);
    });

    for (final Locale locale in AppLocalization.supportedLocales) {
      testWidgets('fits a small phone at the largest font '
          '(${locale.languageCode})', (WidgetTester tester) async {
        tester.view.physicalSize = const Size(320 * 3, 568 * 3);
        tester.view.devicePixelRatio = 3;
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await tester.runAsync(AppHarness.freshInstall);
        await harness.pumpApp(tester, locale: locale);
        expect(find.byType(OnboardingScreen), findsOneWidget);
        expect(tester.takeException(), isNull);

        for (int i = 0; i < OnboardingScreen.pages.length - 1; i++) {
          await AppHarness.tapAndSettle(
            tester,
            find.byWidgetPredicate((Widget w) => w is FilledButton),
          );
          expect(tester.takeException(), isNull, reason: 'leaf ${i + 2}');
        }
      });
    }
  });

  group('what the guide and the introduction say', () {
    test('every step and every leaf has its words in both languages', () {
      for (final String locale in <String>['ar', 'en']) {
        final Map<String, dynamic> strings =
            jsonDecode(
                  File('assets/translations/$locale.json').readAsStringSync(),
                )
                as Map<String, dynamic>;
        String? lookup(String dotted) {
          Object? node = strings;
          for (final String part in dotted.split('.')) {
            node = node is Map<String, dynamic> ? node[part] : null;
          }
          return node is String ? node : null;
        }

        for (final String key in <String>[
          for (final HowToStep s in HowToUseScreen.steps) ...<String>[
            s.titleKey,
            s.bodyKey,
          ],
          for (final OnboardingPage p in OnboardingScreen.pages) ...<String>[
            p.titleKey,
            p.bodyKey,
          ],
        ]) {
          expect(lookup(key)?.trim(), isNotEmpty, reason: '$locale: $key');
        }
      }
    });
  });

  group('about the developer', () {
    Future<void> openDeveloper(WidgetTester tester) async {
      await harness.pumpApp(tester);
      await AppHarness.tapAndSettle(
        tester,
        find.byIcon(Icons.settings_outlined),
      );
      expect(find.byType(SettingsScreen), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('عن المطوّر'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      // The last row on the page: visible is not yet tappable while it is
      // only peeking over the bottom edge.
      await tester.ensureVisible(find.text('عن المطوّر'));
      await tester.pumpAndSettle();
      await AppHarness.tapAndSettle(tester, find.text('عن المطوّر'));
      expect(find.byType(DeveloperScreen), findsOneWidget);
    }

    void useAppInfo(Map<String, dynamic> json) {
      sl.unregister<AppInfoService>();
      sl.registerLazySingleton<AppInfoService>(
        () => offlineAppInfo(_Fixed(jsonEncode(json))),
      );
    }

    _Links useLinks() {
      final _Links links = _Links();
      sl.unregister<LinkOpener>();
      sl.registerLazySingleton<LinkOpener>(() => links);
      return links;
    }

    testWidgets('shows only the ways of reaching them that were filled in', (
      WidgetTester tester,
    ) async {
      useAppInfo(<String, dynamic>{
        'developer': <String, dynamic>{
          'name': <String, String>{'ar': 'فلان', 'en': 'Someone'},
          'email': 'someone@example.com',
          'whatsapp': '+20 100 000 0000',
          'github': '',
          'linkedin': '',
          'facebook': '',
        },
      });
      await openDeveloper(tester);

      expect(find.text('فلان'), findsOneWidget);
      expect(find.text('البريد الإلكتروني'), findsOneWidget);
      expect(find.text('واتساب'), findsOneWidget);
      expect(find.text('GitHub'), findsNothing);
      expect(find.text('LinkedIn'), findsNothing);
      expect(find.text('فيسبوك'), findsNothing);
    });

    testWidgets('a tap hands the address to the device, in a form it opens', (
      WidgetTester tester,
    ) async {
      final _Links links = useLinks();
      await openDeveloper(tester);

      await AppHarness.tapAndSettle(tester, find.text('البريد الإلكتروني'));

      expect(links.opened.single.scheme, 'mailto');
      expect(links.opened.single.path, contains('@'));
    });

    testWidgets('a link nothing will open says so, quietly', (
      WidgetTester tester,
    ) async {
      final _Links links = useLinks()..succeed = false;
      await openDeveloper(tester);

      await AppHarness.tapAndSettle(tester, find.text('البريد الإلكتروني'));

      expect(links.opened, hasLength(1));
      expect(find.text('تعذّر فتح الرابط'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('with nothing to show, shows a card and no empty section', (
      WidgetTester tester,
    ) async {
      useAppInfo(<String, dynamic>{});
      await openDeveloper(tester);

      expect(find.text('مطوّر التطبيق'), findsOneWidget);
      expect(find.text('للتواصل'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
