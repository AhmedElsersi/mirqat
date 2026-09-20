import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mirqat/admin/config/admin_config.dart';
import 'package:mirqat/admin/cubit/app_info_editor_cubit.dart';
import 'package:mirqat/admin/services/admin_file_picker.dart';
import 'package:mirqat/admin/services/app_info_validator.dart';
import 'package:mirqat/admin/services/pages_publisher.dart';
import 'package:mirqat/admin/services/r2_client.dart';
import 'package:mirqat/core/constants/asset_paths.dart';
import 'package:mirqat/data/datasources/asset_reader.dart';
import 'package:mirqat/data/models/app_info.dart';

const String kToken = 'ghp_this_must_never_be_shown';

const AdminConfig config = AdminConfig(
  accountId: 'acc',
  accessKey: 'key',
  secretKey: 'secret',
  bucket: 'iqra-audio',
  endpoint: 'https://acc.r2.cloudflarestorage.com',
  publicBase: 'https://pub-example.r2.dev',
  bitrate: 64,
  githubToken: kToken,
  githubRepo: 'someone/iqra-cdn',
);

const String kStore = 'https://play.google.com/store/apps/details?id=x';

const AppInfo good = AppInfo(
  about: LocalizedText(ar: 'من نحن', en: 'About us'),
  goal: LocalizedText(ar: 'هدفنا', en: 'Our goal'),
  developer: DeveloperInfo(
    name: LocalizedText(ar: 'اسم', en: 'Name'),
    links: <DeveloperLink, String>{DeveloperLink.email: 'a@b.co'},
  ),
  update: UpdateRules(
    android: PlatformUpdate(min: '1.0.0', latest: '1.2.0', storeUrl: kStore),
  ),
);

class _Bundle implements AssetReader {
  @override
  Future<String> loadString(String path) async =>
      File(AssetPaths.bundledAppInfo).readAsStringSync();
}

class _Picker implements AdminFilePicker {
  _Picker(this.image);

  final String? image;

  @override
  Future<String?> pickImage() async => image;

  @override
  Future<String?> pickRecording() async => null;
}

AppInfo withAndroid({String? min, String? latest, String? storeUrl}) =>
    good.copyWith(
      update: good.update.copyWith(
        android: good.update.android.copyWith(
          min: min,
          latest: latest,
          storeUrl: storeUrl,
        ),
      ),
    );

void main() {
  group('what is refused before it can be published', () {
    test('the copy that ships is publishable as it stands', () {
      expect(
        validateAppInfo(
          AppInfo.parse(File(AssetPaths.bundledAppInfo).readAsStringSync()),
        ),
        isEmpty,
      );
    });

    test('a page with one language missing', () {
      expect(
        validateAppInfo(
          good.copyWith(
            about: const LocalizedText(ar: 'نص', en: ' '),
          ),
        ),
        contains(contains('About us has no English')),
      );
    });

    test('a link a phone cannot open', () {
      final List<String> problems = validateAppInfo(
        good.copyWith(
          developer: good.developer.withLink(
            DeveloperLink.email,
            'not-an-email',
          ),
        ),
      );
      expect(problems.single, contains('email'));
    });

    test('a version that is not a version — the app would ignore it, and its '
        'author would not know', () {
      expect(
        validateAppInfo(withAndroid(min: '1.o.0')),
        contains(contains('"1.o.0" is not a version')),
      );
    });

    test('a minimum newer than the latest', () {
      // Everyone below it would be sent to fetch a version that is itself
      // too old.
      expect(
        validateAppInfo(withAndroid(min: '2.0.0', latest: '1.2.0')),
        contains(contains('newer than the latest')),
      );
    });

    test('a rule with no https store page', () {
      for (final String store in <String>[
        '',
        'play.google.com/x',
        'http://x.co',
      ]) {
        expect(
          validateAppInfo(withAndroid(storeUrl: store)),
          contains(contains('no https store page')),
          reason: '"$store"',
        );
      }
    });

    test('a platform with no rule needs no store page', () {
      // iOS, until there is an App Store ID.
      expect(validateAppInfo(good), isEmpty);
    });

    test('"what is new" in one language only', () {
      expect(
        validateAppInfo(
          good.copyWith(
            update: good.update.copyWith(
              notes: const LocalizedText(ar: 'جديد'),
            ),
          ),
        ),
        contains(contains('one language only')),
      );
    });
  });

  group('raising a minimum', () {
    test('is told apart from every other edit', () {
      expect(raisedMinimums(good, good), isEmpty);
      expect(raisedMinimums(good, withAndroid(latest: '1.3.0')), isEmpty);
      // Lowering or clearing one only ever lets more people in.
      expect(raisedMinimums(good, withAndroid(min: '0.9.0')), isEmpty);
      expect(raisedMinimums(good, withAndroid(min: '')), isEmpty);

      expect(raisedMinimums(good, withAndroid(min: '1.1.0')), <String, String>{
        'Android': '1.1.0',
      });
      // A first minimum is a raise too.
      expect(raisedMinimums(withAndroid(min: ''), good), <String, String>{
        'Android': '1.0.0',
      });
    });

    test('is confirmed by typing the versions themselves', () {
      expect(
        confirmationFor(<String, String>{'Android': '1.1.0', 'iOS': '2.0.0'}),
        '1.1.0 2.0.0',
      );
    });
  });

  group('the editor', () {
    late List<http.Request> github;

    AppInfoEditorCubit editor({
      String? live,
      String? image,
      List<http.Request>? r2,
      File? bundledCopy,
    }) {
      github = <http.Request>[];
      final AppInfoEditorCubit cubit = AppInfoEditorCubit(
        pagesPublisher: PagesPublisher(
          adminConfig: config,
          client: MockClient((http.Request request) async {
            github.add(request);
            return request.method == 'GET'
                ? http.Response(jsonEncode(<String, String>{'sha': 'old'}), 200)
                : http.Response(
                    jsonEncode(<String, dynamic>{
                      'commit': <String, String>{'sha': 'abc123'},
                    }),
                    200,
                  );
          }),
        ),
        r2Client: R2Client(
          adminConfig: config,
          client: MockClient((http.Request request) async {
            r2?.add(request);
            return http.Response('', request.method == 'HEAD' ? 404 : 200);
          }),
        ),
        assetReader: _Bundle(),
        filePicker: _Picker(image),
        bundledCopy: bundledCopy,
        client: MockClient(
          (_) async => live == null
              ? http.Response('', 404)
              : http.Response.bytes(utf8.encode(live), 200),
        ),
      );
      addTearDown(cubit.close);
      return cubit;
    }

    Map<String, dynamic> published() =>
        jsonDecode(
              utf8.decode(
                base64Decode(
                  (jsonDecode(
                            github
                                .lastWhere(
                                  (http.Request r) => r.method == 'PUT',
                                )
                                .body,
                          )
                          as Map<String, dynamic>)['content']
                      as String,
                ),
              ),
            )
            as Map<String, dynamic>;

    test('starts from what is live, and says so', () async {
      final AppInfoEditorCubit cubit = editor(live: jsonEncode(good.toJson()));
      await cubit.load();
      expect(cubit.state.source, AppInfoSource.published);
      expect(cubit.state.draft, good);
      expect(cubit.state.dirty, isFalse);
    });

    test('with nothing live, starts from the bundled copy', () async {
      final AppInfoEditorCubit cubit = editor();
      await cubit.load();
      expect(cubit.state.source, AppInfoSource.bundled);
      expect(cubit.state.draft.about.ar, isNotEmpty);
    });

    test(
      'publishes exactly the draft, to app.json beside the manifest',
      () async {
        final AppInfoEditorCubit cubit = editor(
          live: jsonEncode(good.toJson()),
        );
        await cubit.load();
        cubit.edit(
          (AppInfo i) => i.copyWith(
            goal: const LocalizedText(ar: 'هدف جديد', en: 'A new goal'),
          ),
        );

        await cubit.publish();

        final http.Request put = github.lastWhere(
          (http.Request r) => r.method == 'PUT',
        );
        expect(put.url.path, '/repos/someone/iqra-cdn/contents/app.json');
        expect(AppInfo.fromJson(published()), cubit.state.draft);
        expect(published()['goal'], <String, String>{
          'ar': 'هدف جديد',
          'en': 'A new goal',
        });
        expect(
          (jsonDecode(put.body) as Map<String, dynamic>)['message'],
          'Publish app.json: goal',
        );
        // Published is the new baseline: nothing is left to publish.
        expect(cubit.state.dirty, isFalse);
        expect(cubit.state.message, contains('abc123'));
      },
    );

    test(
      'what is published is also written into the app\'s bundled copy',
      () async {
        final Directory dir = Directory.systemTemp.createTempSync('bundle');
        addTearDown(() => dir.deleteSync(recursive: true));
        final File bundled = File('${dir.path}/app.json')
          ..writeAsStringSync('{}');
        final AppInfoEditorCubit cubit = editor(
          live: jsonEncode(good.toJson()),
          bundledCopy: bundled,
        );
        await cubit.load();
        cubit.edit(
          (AppInfo i) => i.copyWith(
            goal: const LocalizedText(ar: 'هدف', en: 'A goal'),
          ),
        );

        await cubit.publish();

        // Byte for byte what went to the site.
        expect(AppInfo.parse(bundled.readAsStringSync()), cubit.state.draft);
        expect(jsonDecode(bundled.readAsStringSync()), published());
        expect(cubit.state.message, contains(bundled.path));
      },
    );

    test('a refused publish leaves the bundled copy alone', () async {
      final Directory dir = Directory.systemTemp.createTempSync('bundle');
      addTearDown(() => dir.deleteSync(recursive: true));
      final File bundled = File('${dir.path}/app.json')
        ..writeAsStringSync('{}');
      final AppInfoEditorCubit cubit = editor(
        live: jsonEncode(good.toJson()),
        bundledCopy: bundled,
      );
      await cubit.load();
      cubit.edit((_) => withAndroid(storeUrl: ''));

      await cubit.publish();

      expect(bundled.readAsStringSync(), '{}');
    });

    test(
      'a bundled copy that cannot be written does not fail the publish',
      () async {
        final AppInfoEditorCubit cubit = editor(
          live: jsonEncode(good.toJson()),
          bundledCopy: File('/nonexistent-dir/for/sure/app.json'),
        );
        await cubit.load();
        cubit.edit(
          (AppInfo i) => i.copyWith(
            goal: const LocalizedText(ar: 'هدف', en: 'A goal'),
          ),
        );

        await cubit.publish();

        expect(
          github.where((http.Request r) => r.method == 'PUT'),
          hasLength(1),
        );
        expect(cubit.state.error, isNull);
        expect(cubit.state.message, contains('by hand'));
      },
    );

    test('refuses a draft with something wrong in it', () async {
      final AppInfoEditorCubit cubit = editor(live: jsonEncode(good.toJson()));
      await cubit.load();
      cubit.edit((_) => withAndroid(storeUrl: ''));

      await cubit.publish();

      expect(github.where((http.Request r) => r.method == 'PUT'), isEmpty);
      expect(cubit.state.error, contains('to fix first'));
    });

    test('a raised minimum is not published on a click', () async {
      final AppInfoEditorCubit cubit = editor(live: jsonEncode(good.toJson()));
      await cubit.load();
      // The slip this exists for: 10.0.0 for 1.0.0.
      cubit.edit((_) => withAndroid(min: '10.0.0', latest: '10.0.0'));
      expect(cubit.state.raised, <String, String>{'Android': '10.0.0'});

      await cubit.publish();
      expect(github.where((http.Request r) => r.method == 'PUT'), isEmpty);
      expect(cubit.state.error, contains('type 10.0.0'));

      await cubit.publish(typedConfirmation: '1.0.0');
      expect(github.where((http.Request r) => r.method == 'PUT'), isEmpty);

      await cubit.publish(typedConfirmation: ' 10.0.0 ');
      expect(github.where((http.Request r) => r.method == 'PUT'), hasLength(1));
      expect(
        (jsonDecode(github.last.body) as Map<String, dynamic>)['message'],
        contains('minimum raised: Android 10.0.0'),
      );
    });

    test('other edits to the rules need no typing', () async {
      final AppInfoEditorCubit cubit = editor(live: jsonEncode(good.toJson()));
      await cubit.load();
      cubit.edit((_) => withAndroid(latest: '1.3.0'));
      await cubit.publish();
      expect(github.where((http.Request r) => r.method == 'PUT'), hasLength(1));
    });

    test('a photo is uploaded under a name made from its own bytes', () async {
      final Directory dir = Directory.systemTemp.createTempSync('photo');
      addTearDown(() => dir.deleteSync(recursive: true));
      final File photo = File('${dir.path}/Me.JPG')
        ..writeAsBytesSync(<int>[1, 2, 3, 4]);
      final List<http.Request> r2 = <http.Request>[];
      final AppInfoEditorCubit cubit = editor(
        live: jsonEncode(good.toJson()),
        image: photo.path,
        r2: r2,
      );
      await cubit.load();

      await cubit.choosePhoto();

      final String url = cubit.state.draft.developer.photo;
      expect(url, startsWith('https://pub-example.r2.dev/images/developer-'));
      expect(url, endsWith('.jpg'));
      // Looked for first and never overwritten: the tool's rule, kept.
      expect(r2.first.method, 'HEAD');
      expect(r2.map((http.Request r) => r.method), isNot(contains('DELETE')));
      expect(cubit.state.dirty, isTrue);

      // The same bytes again: the same address.
      await cubit.choosePhoto();
      expect(cubit.state.draft.developer.photo, url);
    });

    test('cancelling the file panel changes nothing', () async {
      final AppInfoEditorCubit cubit = editor(live: jsonEncode(good.toJson()));
      await cubit.load();
      await cubit.choosePhoto();
      expect(cubit.state.dirty, isFalse);
      expect(cubit.state.error, isNull);
    });

    test('the token is in no message, no error and no state', () async {
      final AppInfoEditorCubit cubit = AppInfoEditorCubit(
        pagesPublisher: PagesPublisher(
          adminConfig: config,
          client: MockClient(
            (http.Request r) async => r.method == 'GET'
                ? http.Response('', 404)
                : http.Response(
                    jsonEncode(<String, String>{'message': 'Bad credentials'}),
                    401,
                  ),
          ),
        ),
        r2Client: R2Client(adminConfig: config),
        assetReader: _Bundle(),
        filePicker: _Picker(null),
        client: MockClient(
          (_) async =>
              http.Response.bytes(utf8.encode(jsonEncode(good.toJson())), 200),
        ),
      );
      addTearDown(cubit.close);
      await cubit.load();
      cubit.edit(
        (AppInfo i) => i.copyWith(
          goal: const LocalizedText(ar: 'هدف', en: 'Goal 2'),
        ),
      );

      await cubit.publish();

      expect(cubit.state.error, contains('401'));
      expect(
        '${cubit.state.error}${cubit.state.message}',
        isNot(contains(kToken)),
      );
      expect(cubit.json, isNot(contains(kToken)));
    });
  });
}
