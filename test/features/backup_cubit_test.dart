import 'package:dartz/dartz.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mirqat/core/localization/app_localization.dart';
import 'package:mirqat/features/backup/screen/backup_screen.dart';
import 'package:mirqat/core/error/failures.dart';
import 'package:mirqat/features/backup/cubit/backup_cubit.dart';
import 'package:mirqat/services/backup_service.dart';
import 'package:mirqat/services/document_picker.dart';
import 'package:mirqat/services/share_service.dart';

import '../localized.dart';

class _Picker extends DocumentPicker {
  _Picker(this.answer);

  final PickedText answer;

  @override
  Future<PickedText> pickText() async => answer;
}

class _Backup implements BackupService {
  final List<String> imported = <String>[];

  @override
  Future<Either<BackupRefusal, BackupMerge>> importContents(
    String contents,
  ) async {
    imported.add(contents);
    return contents == 'good'
        ? const Right<BackupRefusal, BackupMerge>(
            BackupMerge(ayahs: 3, reviews: 1, days: 2),
          )
        : const Left<BackupRefusal, BackupMerge>(BackupRefusal.notABackup);
  }

  @override
  Future<Either<Failure, String>> export() async =>
      const Right<Failure, String>('/docs/mirqat-progress-1.json');

  @override
  Future<List<BackupFile>> list() async => const <BackupFile>[];

  @override
  Future<String?> folder() async => '/docs';

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _Share extends ShareService {
  final List<String> shared = <String>[];

  @override
  Future<bool> shareFile(String path, {required String mimeType}) async {
    shared.add('$path $mimeType');
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BackupCubit cubit(_Backup backup, PickedText answer, [_Share? share]) =>
      BackupCubit(
        backupService: backup,
        shareService: share ?? _Share(),
        picker: _Picker(answer),
      );

  group('a copy chosen from anywhere on the device', () {
    test('is merged in, and the screen says what changed', () async {
      final _Backup backup = _Backup();
      final BackupCubit c = cubit(backup, const Picked('good'));
      addTearDown(c.close);
      await c.importPicked();
      expect(backup.imported, <String>['good']);
      expect(c.state.merged?.ayahs, 3);
      expect(c.state.refusal, isNull);
      expect(c.state.busy, isFalse);
    });

    test('a file that is not a copy is refused, and nothing changes', () async {
      final BackupCubit c = cubit(_Backup(), const Picked('<html>'));
      addTearDown(c.close);
      await c.importPicked();
      expect(c.state.refusal, BackupRefusal.notABackup);
      expect(c.state.merged, isNull);
    });

    test('closing the picker says nothing at all', () async {
      final _Backup backup = _Backup();
      final BackupCubit c = cubit(backup, const PickCancelled());
      addTearDown(c.close);
      await c.importPicked();
      expect(backup.imported, isEmpty);
      expect(c.state.refusal, isNull);
      expect(c.state.merged, isNull);
      expect(c.state.busy, isFalse);
    });

    test('a file that cannot be read says so', () async {
      final BackupCubit c = cubit(_Backup(), const PickFailed());
      addTearDown(c.close);
      await c.importPicked();
      expect(c.state.refusal, BackupRefusal.unreadable);
    });
  });

  test('the copy just saved is handed to the share sheet as JSON', () async {
    final _Share share = _Share();
    final BackupCubit c = cubit(_Backup(), const PickCancelled(), share);
    addTearDown(c.close);
    await c.shareExported();
    expect(share.shared, isEmpty, reason: 'nothing saved yet');
    await c.export();
    await c.shareExported();
    expect(share.shared, <String>[
      '/docs/mirqat-progress-1.json application/json',
    ]);
  });

  group('the picker channel', () {
    const MethodChannel channel = MethodChannel('com.mirqat.app/files');
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    void answer(Future<Object?> Function(MethodCall) handler) =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, handler);

    test('contents, a cancel, a failure, and no platform at all', () async {
      answer((MethodCall call) async {
        expect(call.method, 'pickText');
        return '{"a":1}';
      });
      final PickedText picked = await const DocumentPicker(channel).pickText();
      expect(picked, isA<Picked>());
      expect((picked as Picked).text, '{"a":1}');

      answer((MethodCall _) async => null);
      expect(
        await const DocumentPicker(channel).pickText(),
        isA<PickCancelled>(),
      );

      answer(
        (MethodCall _) async => throw PlatformException(code: 'unreadable'),
      );
      expect(await const DocumentPicker(channel).pickText(), isA<PickFailed>());

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      expect(
        await const DocumentPicker(channel).pickText(),
        isA<PickCancelled>(),
      );
    });
  });

  group('the screen', () {
    setUpAll(ensureTestLocalization);
    tearDown(() => GetIt.instance.reset());

    for (final Locale locale in AppLocalization.supportedLocales) {
      final bool ar = locale.languageCode == 'ar';
      testWidgets('offers choosing a copy, and sending one once saved, at '
          '320 dp in ${locale.languageCode}', (WidgetTester tester) async {
        GetIt.instance.registerFactory<BackupCubit>(
          () => cubit(_Backup(), const PickCancelled()),
        );
        Intl.defaultLocale = locale.toString();
        addTearDown(() => Intl.defaultLocale = null);
        tester.view.physicalSize = const Size(320, 900);
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
                home: const BackupScreen(),
              ),
            ),
            locale: locale,
          ),
        );
        await settleLocalization(tester);
        expect(
          find.text(ar ? 'اختر ملف نسخة…' : 'Choose a copy…'),
          findsOneWidget,
        );

        await tester.runAsync(() async {
          await tester.tap(find.text(ar ? 'احفظ الآن' : 'Save now'));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pump();
        expect(
          find.text(
            ar
                ? 'أرسل النسخة أو احفظها في مكان آخر'
                : 'Send or save the copy elsewhere',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
