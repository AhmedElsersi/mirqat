import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dartz/dartz.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mirqat/core/error/exceptions.dart';
import 'package:mirqat/core/error/failures.dart';
import 'package:mirqat/core/localization/app_localization.dart';
import 'package:mirqat/core/state/load_status.dart';
import 'package:mirqat/data/datasources/asset_reader.dart';
import 'package:mirqat/data/datasources/quran_database.dart';
import 'package:mirqat/data/datasources/quran_local_data_source.dart';
import 'package:mirqat/data/datasources/quran_pages_local_data_source.dart';
import 'package:mirqat/data/models/word.dart';
import 'package:mirqat/data/repositories/mutashabihat_repository.dart';
import 'package:mirqat/data/repositories/progress_repository.dart';
import 'package:mirqat/data/repositories/quran_pages_repository.dart';
import 'package:mirqat/data/repositories/quran_repository.dart';
import 'package:mirqat/domain/entities/ayah_ref.dart';
import 'package:mirqat/features/similar/cubit/drill_cubit.dart';
import 'package:mirqat/features/similar/screen/drill_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../app_harness.dart' show FileAssetReader;
import '../localized.dart';

/// Phrase 1 closes 2:62, 2:112 and 5:69; phrase 2 opens 2:23 and 2:62.
final Map<String, Object?> sample = <String, Object?>{
  'schemaVersion': 1,
  'source': 't',
  'phrases': <Map<String, Object?>>[
    <String, Object?>{
      'id': 1,
      'ayahs': <List<int>>[
        <int>[2, 62, 19, 24],
        <int>[2, 112, 12, 17],
        <int>[5, 69, 15, 20],
      ],
    },
    <String, Object?>{
      'id': 2,
      'ayahs': <List<int>>[
        <int>[2, 23, 1, 2],
        <int>[2, 62, 1, 2],
      ],
    },
  ],
};

class _Assets implements AssetReader {
  @override
  Future<String> loadString(String path) async =>
      path == 'assets/data/mutashabihat.json'
      ? jsonEncode(sample)
      : throw AssetNotFoundException(path, 'absent');
}

/// Records the stumbles a drill notes.
class _Progress implements ProgressRepository {
  final List<AyahRef> stumbles = <AyahRef>[];

  @override
  Future<Either<Failure, Unit>> markStumble(
    int surahNumber,
    int ayahNumber, {
    DateTime? at,
  }) async {
    stumbles.add(AyahRef(surahNumber, ayahNumber));
    return const Right<Failure, Unit>(unit);
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late QuranDatabase db;
  late _Progress progress;

  DrillCubit drill() => DrillCubit(
    mutashabihatRepository: MutashabihatRepository(_Assets()),
    quranRepository: QuranRepositoryImpl(
      QuranLocalDataSourceImpl(const FileAssetReader(), db),
    ),
    pagesRepository: QuranPagesRepositoryImpl(
      QuranPagesLocalDataSourceImpl(db),
    ),
    progressRepository: progress,
    random: Random(7),
  );

  setUp(() {
    sqfliteFfiInit();
    dir = Directory.systemTemp.createTempSync('drill_test');
    db = QuranDatabase(
      factory: databaseFactoryFfiNoIsolate,
      resolveStorageDirectory: () async => dir,
    );
    progress = _Progress();
  });
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('the rounds', () {
    test(
      'one per ayah of the phrase, each choice list holding the answer',
      () async {
        final DrillCubit cubit = drill();
        addTearDown(cubit.close);
        await cubit.load(1);

        expect(cubit.state.status, LoadStatus.ready);
        expect(
          cubit.state.rounds.map((DrillRound r) => r.ayah.ref).toSet(),
          <AyahRef>{
            const AyahRef(2, 62),
            const AyahRef(2, 112),
            const AyahRef(5, 69),
          },
        );
        for (final DrillRound r in cubit.state.rounds) {
          final List<AyahRef> refs = <AyahRef>[
            for (final DrillChoice c in r.choices) c.ref,
          ];
          expect(refs, contains(r.ayah.ref));
          expect(refs.toSet(), hasLength(refs.length));
          expect(refs.length, lessThanOrEqualTo(DrillCubit.maxChoices));
        }
      },
    );

    test('shown up to the end of the phrase; the rest, and the number, held '
        'back', () async {
      final DrillCubit cubit = drill();
      addTearDown(cubit.close);
      await cubit.load(1);
      final DrillRound r = cubit.state.rounds.firstWhere(
        (DrillRound r) => r.ayah.ref == const AyahRef(5, 69),
      );
      final List<int> shown = <int>[
        for (final Word w in r.ayah.words)
          if (!r.isHeldBack(w)) w.position,
      ];
      expect(shown, <int>[for (int i = 1; i <= 20; i++) i]);
      expect(
        r.ayah.words.where(r.isHeldBack).every((Word w) => w.isMarker),
        isTrue,
        reason: '5:69 ends on the phrase: only its number is held back',
      );
      // The phrase closes the ayah: the continuation is the next one.
      expect(r.after, isNotEmpty);
      expect(r.after.first.ayahNumber, 70);
      expect(r.before, isEmpty);
    });

    test(
      'a phrase that opens its ayah shows the ayah before, for context',
      () async {
        final DrillCubit cubit = drill();
        addTearDown(cubit.close);
        await cubit.load(2);
        final DrillRound r = cubit.state.rounds.firstWhere(
          (DrillRound r) => r.ayah.ref == const AyahRef(2, 23),
        );
        expect(r.before.first.ayahNumber, 22);
        expect(r.after, isEmpty);
      },
    );

    test('a phrase the index does not hold is a failure', () async {
      final DrillCubit cubit = drill();
      addTearDown(cubit.close);
      await cubit.load(99);
      expect(cubit.state.status, LoadStatus.failure);
    });
  });

  group('a round, played', () {
    test('pick, show, say how it went; a slip is noted as a stumble', () async {
      final DrillCubit cubit = drill();
      addTearDown(cubit.close);
      await cubit.load(1);

      // Out of order does nothing.
      cubit.reveal();
      expect(cubit.state.stage, DrillStage.identify);

      final DrillRound first = cubit.state.round!;
      final AyahRef wrong = first.choices
          .firstWhere((DrillChoice c) => c.ref != first.ayah.ref)
          .ref;
      cubit.pick(wrong);
      expect(cubit.state.stage, DrillStage.recite);
      expect(cubit.state.pickedRight, isFalse);

      cubit.reveal();
      expect(cubit.state.stage, DrillStage.revealed);
      await cubit.grade(slipped: true);
      expect(progress.stumbles, <AyahRef>[first.ayah.ref]);
      expect(cubit.state.slips, 1);
      expect(cubit.state.index, 1);
      expect(cubit.state.stage, DrillStage.identify);
      expect(cubit.state.picked, isNull);

      // The rest, held, ends the drill.
      for (int i = 1; i < cubit.state.rounds.length; i++) {
        cubit.pick(cubit.state.round!.ayah.ref);
        expect(cubit.state.pickedRight, isTrue);
        cubit.reveal();
        await cubit.grade(slipped: false);
      }
      expect(cubit.state.stage, DrillStage.done);
      expect(cubit.state.round, isNull);
      expect(progress.stumbles, hasLength(1));

      await cubit.restart();
      expect(cubit.state.stage, DrillStage.identify);
      expect(cubit.state.slips, 0);
      expect(cubit.state.index, 0);
    });
  });

  group('the screen', () {
    setUpAll(ensureTestLocalization);
    setUp(() => GetIt.instance.registerFactory<DrillCubit>(drill));
    tearDown(() => GetIt.instance.reset());

    Future<void> letLand(WidgetTester tester) async {
      for (int i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    for (final Locale locale in AppLocalization.supportedLocales) {
      final bool ar = locale.languageCode == 'ar';
      testWidgets('a round, played through at 320 dp, in '
          '${locale.languageCode}', (WidgetTester tester) async {
        Intl.defaultLocale = locale.toString();
        addTearDown(() => Intl.defaultLocale = null);
        tester.view.physicalSize = const Size(320, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          localized(
            ScreenUtilInit(
              designSize: const Size(390, 844),
              builder: (BuildContext context, _) => MaterialApp(
                locale: context.locale,
                supportedLocales: context.supportedLocales,
                localizationsDelegates: context.localizationDelegates,
                home: const DrillScreen(phraseId: 1),
              ),
            ),
            locale: locale,
          ),
        );
        await settleLocalization(tester);
        await letLand(tester);
        expect(tester.takeException(), isNull);

        expect(
          find.text(ar ? 'أيّ آية هذه؟' : 'Which ayah is this?'),
          findsOneWidget,
        );
        // Three choices; on a small phone the last may be a scroll away.
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
        await tester.pump();
        expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(3));
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
        await tester.pump();

        // The first choice may sit under the fold on a small phone.
        await tester.ensureVisible(
          find.byIcon(Icons.radio_button_unchecked).first,
        );
        await tester.pump();
        await tester.tap(find.byIcon(Icons.radio_button_unchecked).first);
        await tester.pump();
        // The choices stay on screen, picked; the reveal is under them.
        await tester.scrollUntilVisible(
          find.text(ar ? 'اكشف الباقي' : 'Show the rest'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text(ar ? 'اكشف الباقي' : 'Show the rest'));
        await tester.pump();
        expect(find.text(ar ? 'أتممتها' : 'I had it'), findsOneWidget);
        expect(find.text(ar ? 'تعثّرت' : 'I slipped'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.runAsync(() async {
          await tester.tap(find.text(ar ? 'أتممتها' : 'I had it'));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pump();
        expect(
          find.text(ar ? 'الجولة ٢ من ٣' : 'Round 2 of 3'),
          findsOneWidget,
        );
      });
    }
  });
}
