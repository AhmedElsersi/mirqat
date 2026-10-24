import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/error/failures.dart';
import 'package:mirqat/core/theme/app_text_styles.dart';
import 'package:mirqat/core/theme/quran_font.dart';
import 'package:mirqat/core/widgets/ayah_text.dart';
import 'package:mirqat/data/models/app_settings.dart';
import 'package:mirqat/data/repositories/settings_repository.dart';
import 'package:mirqat/features/settings/cubit/settings_cubit.dart';
import 'package:mirqat/features/settings/screen/mushaf_font_screen.dart';

import '../quran_db_fixtures.dart';

/// The family a rendered [AyahText] ended up in.
String? familyOf(WidgetTester tester, Finder ayah) {
  final Iterable<RichText> texts = tester.widgetList<RichText>(
    find.descendant(of: ayah, matching: find.byType(RichText)),
  );
  return texts.first.text.style?.fontFamily ??
      (texts.first.text as TextSpan).children?.first.style?.fontFamily;
}

void main() {
  group('the face reaches every AyahText under its scope', () {
    Future<void> pump(WidgetTester tester, QuranFont? font) async {
      final Widget ayahs = Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: <Widget>[
            const AyahText(key: Key('one'), text: 'ءا', fontSize: 20),
            const AyahText.word(key: Key('word'), text: 'ءا', fontSize: 20),
            AyahText.flowing(
              key: const Key('flow'),
              ayahs: const <FlowingAyah>[FlowingAyah(number: 1, text: 'ءا')],
              fontSize: 20,
            ),
          ],
        ),
      );
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            home: font == null
                ? ayahs
                : QuranFontScope(font: font, child: ayahs),
          ),
        ),
      );
    }

    testWidgets('no scope: the default face', (WidgetTester tester) async {
      await pump(tester, null);
      for (final String k in <String>['one', 'word', 'flow']) {
        expect(
          familyOf(tester, find.byKey(Key(k))),
          AppTextStyles.quranFamilyOf(QuranFont.fallback),
          reason: k,
        );
      }
    });

    testWidgets('a scope: its face, in all three constructors', (
      WidgetTester tester,
    ) async {
      await pump(tester, QuranFont.hafsV18);
      for (final String k in <String>['one', 'word', 'flow']) {
        expect(
          familyOf(tester, find.byKey(Key(k))),
          AppTextStyles.quranFamilyOf(QuranFont.hafsV18),
          reason: k,
        );
      }
    });

    test('each bundled face has a family of its own; the fetched one draws '
        'its text in the default face, its pages in per-page families', () {
      final List<QuranFont> bundled = <QuranFont>[
        for (final QuranFont f in QuranFont.values)
          if (f.assetPath != null) f,
      ];
      expect(
        bundled.map(AppTextStyles.quranFamilyOf).toSet(),
        hasLength(bundled.length),
      );
      expect(
        AppTextStyles.quranFamilyOf(QuranFont.qpcV2),
        AppTextStyles.quranFontFamily,
      );
      expect(
        AppTextStyles.qpcPageFamily(3),
        isNot(AppTextStyles.qpcPageFamily(4)),
      );
    });
  });

  group('the mushaf font screen', () {
    late _Settings settings;
    late SettingsCubit cubit;

    Future<void> open(WidgetTester tester) async {
      settings = _Settings(const AppSettings());
      cubit = SettingsCubit(
        settingsRepository: settings,
        reciterCatalog: fixtureCatalog(),
        quranRepository: fixtureRepository(),
      );
      addTearDown(cubit.close);
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            home: BlocProvider<SettingsCubit>.value(
              value: cubit,
              child: const MushafFontScreen(),
            ),
          ),
        ),
      );
      // The preview ayah is read from the database: off the fake clock.
      await tester.runAsync(() async {
        await cubit.load();
        for (int i = 0; i < 100 && cubit.state.previewAyah == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump();
    }

    testWidgets('shows a real ayah, every face offered, and the size', (
      WidgetTester tester,
    ) async {
      await open(tester);
      expect(cubit.state.previewAyah, isNotNull);
      expect(tester.takeException(), isNull);
      // The preview alone is scripture; each face is a named row.
      expect(find.byType(AyahText), findsOneWidget);
      expect(
        find.byType(RadioListTile<QuranFont>),
        findsNWidgets(QuranFont.values.length),
      );
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('choosing a face saves it, and the preview follows at once', (
      WidgetTester tester,
    ) async {
      await open(tester);
      await tester.tap(
        find.byWidgetPredicate(
          (Widget w) =>
              w is RadioListTile<QuranFont> && w.value == QuranFont.hafsV18,
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();

      expect(settings.saved.last.quranFont, QuranFont.hafsV18);
      expect(
        familyOf(tester, find.byType(AyahText).first),
        AppTextStyles.quranFamilyOf(QuranFont.hafsV18),
      );
    });
  });

  test('the chosen face survives the storage map', () {
    const AppSettings s = AppSettings(quranFont: QuranFont.hafsV18);
    expect(AppSettings.fromMap(s.toMap()), s);
    expect(
      AppSettings.fromMap(<String, dynamic>{'quranFont': 'amiri'}).quranFont,
      QuranFont.fallback,
    );
  });
}

class _Settings implements SettingsRepository {
  _Settings(this._current);

  AppSettings _current;
  final List<AppSettings> saved = <AppSettings>[];

  @override
  Future<Either<Failure, AppSettings>> read() async =>
      Right<Failure, AppSettings>(_current);

  @override
  Future<Either<Failure, AppSettings>> save(AppSettings s) async {
    _current = s;
    saved.add(s);
    return Right<Failure, AppSettings>(s);
  }

  @override
  Stream<AppSettings> get changes => const Stream<AppSettings>.empty();
}
