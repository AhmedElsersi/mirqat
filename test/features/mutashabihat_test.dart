import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mirqat/core/error/exceptions.dart';
import 'package:mirqat/core/localization/app_localization.dart';
import 'package:mirqat/core/state/load_status.dart';
import 'package:mirqat/core/widgets/ayah_text.dart';
import 'package:mirqat/core/widgets/panel.dart';
import 'package:mirqat/data/datasources/asset_reader.dart';
import 'package:mirqat/data/datasources/quran_database.dart';
import 'package:mirqat/data/datasources/quran_local_data_source.dart';
import 'package:mirqat/data/datasources/quran_pages_local_data_source.dart';
import 'package:mirqat/data/models/mutashabihat.dart';
import 'package:mirqat/data/models/word.dart';
import 'package:mirqat/data/repositories/mutashabihat_repository.dart';
import 'package:mirqat/data/repositories/quran_pages_repository.dart';
import 'package:mirqat/data/repositories/quran_repository.dart';
import 'package:mirqat/domain/entities/ayah_ref.dart';
import 'package:mirqat/features/similar/cubit/mutashabihat_cubit.dart';
import 'package:mirqat/features/similar/cubit/phrase_cubit.dart';
import 'package:mirqat/features/similar/cubit/similar_cubit.dart';
import 'package:mirqat/features/similar/screen/mutashabihat_screen.dart';
import 'package:mirqat/features/similar/screen/phrase_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../app_harness.dart' show FileAssetReader;
import '../localized.dart';

Map<String, Object?> data(List<Map<String, Object?>> phrases) =>
    <String, Object?>{'schemaVersion': 1, 'source': 't', 'phrases': phrases};

/// Phrase 1 — "… وَلَا خَوۡفٌ عَلَيۡهِمۡ وَلَا هُمۡ يَحۡزَنُونَ" — closes 2:62,
/// 2:112 and 5:69; phrase 2 opens 2:23 and 2:62. Listed out of mushaf order
/// on purpose.
final Map<String, Object?> sample = data(<Map<String, Object?>>[
  <String, Object?>{
    'id': 1,
    'ayahs': <List<int>>[
      <int>[5, 69, 15, 20],
      <int>[2, 112, 12, 17],
      <int>[2, 62, 19, 24],
    ],
  },
  <String, Object?>{
    'id': 2,
    'ayahs': <List<int>>[
      <int>[2, 62, 1, 2],
      <int>[2, 23, 1, 2],
    ],
  },
]);

class _Assets implements AssetReader {
  _Assets(this.files);

  final Map<String, String> files;

  @override
  Future<String> loadString(String path) async =>
      files[path] ?? (throw AssetNotFoundException(path, 'absent'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the index, browsed', () {
    final MutashabihatIndex index = MutashabihatIndex.fromJson(sample);

    test('lists every phrase in the order the mushaf first reaches it', () {
      // Phrase 2 starts at 2:23; phrase 1 not until 2:62.
      expect(index.phraseIds, <int>[2, 1]);
    });

    test('a phrase\'s occurrences come in mushaf order', () {
      expect(
        index.occurrencesOf(1).map((PhraseOccurrence o) => o.ref),
        <AyahRef>[
          const AyahRef(2, 62),
          const AyahRef(2, 112),
          const AyahRef(5, 69),
        ],
      );
      expect(index.occurrencesOf(99), isEmpty);
    });

    test(
      'two phrases starting in one ayah are ordered by where they start',
      () {
        final MutashabihatIndex same = MutashabihatIndex.fromJson(
          data(<Map<String, Object?>>[
            <String, Object?>{
              'id': 7,
              'ayahs': <List<int>>[
                <int>[2, 62, 19, 24],
                <int>[5, 69, 15, 20],
              ],
            },
            <String, Object?>{
              'id': 9,
              'ayahs': <List<int>>[
                <int>[2, 62, 1, 2],
                <int>[2, 23, 1, 2],
              ],
            },
          ]),
        );
        // Phrase 9 is first reached at 2:23, before 2:62.
        expect(same.phraseIds, <int>[9, 7]);
      },
    );
  });

  late Directory dir;
  late QuranDatabase db;

  MutashabihatRepository repo(Map<String, Object?>? json) =>
      MutashabihatRepository(
        _Assets(<String, String>{
          if (json != null) 'assets/data/mutashabihat.json': jsonEncode(json),
        }),
      );
  QuranRepository quran() => QuranRepositoryImpl(
    QuranLocalDataSourceImpl(const FileAssetReader(), db),
  );
  QuranPagesRepository pages() =>
      QuranPagesRepositoryImpl(QuranPagesLocalDataSourceImpl(db));

  setUp(() {
    sqfliteFfiInit();
    dir = Directory.systemTemp.createTempSync('mutashabihat_test');
    db = QuranDatabase(
      factory: databaseFactoryFfiNoIsolate,
      resolveStorageDirectory: () async => dir,
    );
  });
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<List<String>> rawWords(int surah, int ayah) async {
    final Database raw = await databaseFactoryFfi.openDatabase(
      File('assets/data/quran.db').absolute.path,
      options: OpenDatabaseOptions(readOnly: true),
    );
    final List<Map<String, Object?>> rows = await raw.query(
      'words',
      where: 'surah = ? AND ayah = ? AND is_marker = 0',
      whereArgs: <int>[surah, ayah],
      orderBy: 'id',
    );
    await raw.close();
    return <String>[
      for (final Map<String, Object?> r in rows) r['text']! as String,
    ];
  }

  group('the list', () {
    test('a card per phrase, with its ayahs and its surahs', () async {
      final MutashabihatCubit cubit = MutashabihatCubit(
        mutashabihatRepository: repo(sample),
        quranRepository: quran(),
        pagesRepository: pages(),
      );
      addTearDown(cubit.close);
      await cubit.load();

      expect(cubit.state.status, LoadStatus.ready);
      expect(cubit.state.entries.map((PhraseEntry e) => e.id), <int>[2, 1]);
      final PhraseEntry one = cubit.state.entries.last;
      expect(one.ayahCount, 3);
      expect(one.surahs.map((s) => s.number), <int>[2, 5]);
      expect(one.first.ref, const AyahRef(2, 62));
      expect(cubit.state.surahs.map((s) => s.number), <int>[2, 5]);
    });

    test('narrowed to a surah, and back to all of them', () async {
      final MutashabihatCubit cubit = MutashabihatCubit(
        mutashabihatRepository: repo(sample),
        quranRepository: quran(),
        pagesRepository: pages(),
      );
      addTearDown(cubit.close);
      await cubit.load();

      cubit.filterBySurah(5);
      expect(cubit.state.shown.map((PhraseEntry e) => e.id), <int>[1]);
      cubit.filterBySurah(null);
      expect(cubit.state.shown.map((PhraseEntry e) => e.id), <int>[2, 1]);
    });

    test('a phrase\'s words are quran.db\'s own, byte for byte, and all of '
        'them', () async {
      final MutashabihatCubit cubit = MutashabihatCubit(
        mutashabihatRepository: repo(sample),
        quranRepository: quran(),
        pagesRepository: pages(),
      );
      addTearDown(cubit.close);
      await cubit.load();

      final List<Word> words = await cubit.wordsOf(cubit.state.entries.last);
      expect(
        words.map((Word w) => w.text),
        (await rawWords(2, 62)).sublist(18, 24),
      );
      expect(words.any((Word w) => w.isMarker), isFalse);
      // Read once and kept.
      expect(
        identical(
          cubit.wordsOf(cubit.state.entries.last),
          cubit.wordsOf(cubit.state.entries.last),
        ),
        isTrue,
      );
    });

    test('no data imported: ready, and nothing to show', () async {
      final MutashabihatCubit cubit = MutashabihatCubit(
        mutashabihatRepository: repo(null),
        quranRepository: quran(),
        pagesRepository: pages(),
      );
      addTearDown(cubit.close);
      await cubit.load();
      expect(cubit.state.status, LoadStatus.ready);
      expect(cubit.state.entries, isEmpty);
    });
  });

  group('one phrase', () {
    test('every ayah it occurs in, surah by surah, the phrase marked in '
        'each', () async {
      final PhraseCubit cubit = PhraseCubit(
        mutashabihatRepository: repo(sample),
        quranRepository: quran(),
        pagesRepository: pages(),
      );
      addTearDown(cubit.close);
      await cubit.load(1);

      expect(cubit.state.status, LoadStatus.ready);
      expect(cubit.state.groups.map((PhraseGroup g) => g.surah.number), <int>[
        2,
        5,
      ]);
      expect(
        cubit.state.groups.first.ayahs.map((ComparedAyah a) => a.ref),
        <AyahRef>[const AyahRef(2, 62), const AyahRef(2, 112)],
      );
      expect(cubit.state.ayahCount, 3);

      final ComparedAyah maidah = cubit.state.groups.last.ayahs.single;
      expect(
        <int>[
          for (final Word w in maidah.words)
            if (maidah.isShared(w)) w.position,
        ],
        <int>[15, 16, 17, 18, 19, 20],
      );
      // The whole ayah is shown, its marker with it — never cut to the phrase.
      expect(maidah.words.last.isMarker, isTrue);
      expect(
        maidah.words.where((Word w) => !w.isMarker).map((Word w) => w.text),
        await rawWords(5, 69),
      );

      expect(
        cubit.state.words.map((Word w) => w.text),
        (await rawWords(2, 62)).sublist(18, 24),
      );
    });

    test(
      'a phrase the index does not hold is a failure, not an empty page',
      () async {
        final PhraseCubit cubit = PhraseCubit(
          mutashabihatRepository: repo(sample),
          quranRepository: quran(),
          pagesRepository: pages(),
        );
        addTearDown(cubit.close);
        await cubit.load(99);
        expect(cubit.state.status, LoadStatus.failure);
      },
    );
  });

  group('the screens', () {
    setUpAll(ensureTestLocalization);

    setUp(() {
      GetIt.instance
        ..registerFactory<MutashabihatCubit>(
          () => MutashabihatCubit(
            mutashabihatRepository: repo(sample),
            quranRepository: quran(),
            pagesRepository: pages(),
          ),
        )
        ..registerFactory<PhraseCubit>(
          () => PhraseCubit(
            mutashabihatRepository: repo(sample),
            quranRepository: quran(),
            pagesRepository: pages(),
          ),
        );
    });
    tearDown(() => GetIt.instance.reset());

    Future<void> pump(WidgetTester tester, Widget screen, Locale locale) async {
      Intl.defaultLocale = locale.toString();
      addTearDown(() => Intl.defaultLocale = null);
      tester.view.physicalSize = const Size(320, 640);
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
              home: screen,
            ),
          ),
          locale: locale,
        ),
      );
      await settleLocalization(tester);
      // The database reads are real I/O: let them land.
      for (int i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    for (final Locale locale in AppLocalization.supportedLocales) {
      final bool ar = locale.languageCode == 'ar';

      testWidgets('the list lays out at 320 dp, in ${locale.languageCode}', (
        WidgetTester tester,
      ) async {
        await pump(tester, const MutashabihatScreen(), locale);
        expect(tester.takeException(), isNull);
        expect(find.byType(AppCard), findsNWidgets(2));
        // Each card's phrase is drawn through AyahText.
        expect(find.byType(AyahText), findsWidgets);
        // The counts are two tags now, not one line joined by a dot.
        expect(find.text(ar ? 'الآيات: ٣' : 'Ayahs: 3'), findsOneWidget);
        expect(find.text(ar ? 'السور: ٢' : 'Surahs: 2'), findsOneWidget);
        expect(
          find.text(ar ? 'البقرة، المائدة' : 'Al-Baqarah, Al-Ma\'idah'),
          findsOneWidget,
        );
      });

      testWidgets('one phrase lays out at 320 dp, in ${locale.languageCode}', (
        WidgetTester tester,
      ) async {
        await pump(tester, const PhraseScreen(phraseId: 1), locale);
        expect(tester.takeException(), isNull);
        expect(
          find.text(
            ar ? 'سورة البقرة · الآيات: ٢' : 'Surah Al-Baqarah · Ayahs: 2',
          ),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(
          find.text(
            ar ? 'سورة المائدة · الآيات: ١' : 'Surah Al-Ma\'idah · Ayahs: 1',
          ),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
