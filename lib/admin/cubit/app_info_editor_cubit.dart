import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../core/constants/asset_paths.dart';
import '../../core/constants/cdn.dart';
import '../../core/error/exceptions.dart';
import '../../data/datasources/asset_reader.dart';
import '../../data/models/app_info.dart';
import '../services/admin_file_picker.dart';
import '../services/app_info_validator.dart';
import '../services/pages_publisher.dart';
import '../services/r2_client.dart';

/// Where the text in the editor came from.
enum AppInfoSource {
  /// What is live on the Pages site right now.
  published,

  /// The copy bundled with this build — nothing is published yet, or the
  /// site could not be reached.
  bundled,
}

class AppInfoEditorState extends Equatable {
  const AppInfoEditorState({
    this.loading = true,
    this.source = AppInfoSource.bundled,
    this.published = AppInfo.empty,
    this.draft = AppInfo.empty,
    this.busy = false,
    this.message,
    this.error,
  });

  final bool loading;
  final AppInfoSource source;

  /// What the editor started from: the file as it is live, or the bundled
  /// copy. What a raised minimum is measured against.
  final AppInfo published;
  final AppInfo draft;

  /// Uploading a photo, or publishing.
  final bool busy;

  final String? message;
  final String? error;

  bool get dirty => draft != published;

  List<String> get problems => validateAppInfo(draft);

  /// The minimums this draft raises, by platform — each one locks out every
  /// install below it.
  Map<String, String> get raised => raisedMinimums(published, draft);

  AppInfoEditorState copyWith({
    bool? loading,
    AppInfoSource? source,
    AppInfo? published,
    AppInfo? draft,
    bool? busy,
    String? message,
    String? error,
  }) => AppInfoEditorState(
    loading: loading ?? this.loading,
    source: source ?? this.source,
    published: published ?? this.published,
    draft: draft ?? this.draft,
    busy: busy ?? this.busy,
    // Both are about the last thing that happened, so both are replaced.
    message: message,
    error: error,
  );

  @override
  List<Object?> get props => <Object?>[
    loading,
    source,
    published,
    draft,
    busy,
    message,
    error,
  ];
}

/// Edits `app.json` — About us, Our goal, the developer's card, the update
/// rules — and publishes it to the Pages site beside the manifest, where the
/// app picks it up without a release.
class AppInfoEditorCubit extends Cubit<AppInfoEditorState> {
  AppInfoEditorCubit({
    required PagesPublisher pagesPublisher,
    required R2Client r2Client,
    required AssetReader assetReader,
    required AdminFilePicker filePicker,
    http.Client? client,
    this.url = kAppInfoUrl,
    this.bundledCopy,
  }) : _pages = pagesPublisher,
       _r2 = r2Client,
       _assets = assetReader,
       _files = filePicker,
       _client = client ?? http.Client(),
       super(const AppInfoEditorState());

  final PagesPublisher _pages;
  final R2Client _r2;
  final AssetReader _assets;
  final AdminFilePicker _files;
  final http.Client _client;
  final String url;

  /// The app's own bundled `app.json`, in the checkout the tool was started
  /// from. Written after a publish, so that a fresh install — offline, before
  /// its first fetch — starts from the words that are live. Null when the tool
  /// does not know where the checkout is.
  final File? bundledCopy;

  /// Starts from what is live, so that an edit is an edit of what people are
  /// reading now and not of whatever this checkout happens to bundle. Falls
  /// back to the bundled copy — the first publish, or no connection — and
  /// says which it was.
  Future<void> load() async {
    emit(state.copyWith(loading: true));
    AppInfo info = AppInfo.empty;
    AppInfoSource source = AppInfoSource.published;
    try {
      final http.Response response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        info = AppInfo.parse(utf8.decode(response.bodyBytes));
      }
    } on Object {
      // Falls through to the bundled copy.
    }
    if (info == AppInfo.empty) {
      source = AppInfoSource.bundled;
      try {
        info = AppInfo.parse(
          await _assets.loadString(AssetPaths.bundledAppInfo),
        );
      } on Object {
        info = AppInfo.empty;
      }
    }
    if (isClosed) return;
    emit(
      AppInfoEditorState(
        loading: false,
        source: source,
        published: info,
        draft: info,
      ),
    );
  }

  void edit(AppInfo Function(AppInfo draft) change) =>
      emit(state.copyWith(draft: change(state.draft)));

  /// Puts the draft back to what it was loaded as.
  void revert() => emit(state.copyWith(draft: state.published));

  /// Uploads a portrait to the bucket and points the card at it.
  ///
  /// Named by its own contents, so a new photo is a new path and an old
  /// address never starts showing a different face — and so that the tool's
  /// rule against overwriting a published path is kept without an exception.
  Future<void> choosePhoto() async {
    final String? path;
    try {
      path = await _files.pickImage();
    } on Object catch (e) {
      emit(state.copyWith(error: 'The file panel could not be opened: $e'));
      return;
    }
    if (path == null) return;

    emit(state.copyWith(busy: true));
    try {
      final File file = File(path);
      final List<int> bytes = await file.readAsBytes();
      final String key =
          'images/developer-${sha256.convert(bytes).toString().substring(0, 12)}'
          '${p.extension(path).toLowerCase()}';
      final UploadResult uploaded = await _r2.putObject(
        key: key,
        bytes: bytes,
        contentType: _imageTypeFor(path),
      );
      emit(
        state.copyWith(
          busy: false,
          draft: state.draft.copyWith(
            developer: state.draft.developer.copyWith(photo: '${uploaded.url}'),
          ),
          message: 'Photo uploaded. Publish to put it on the card.',
        ),
      );
    } on AppException catch (e) {
      emit(state.copyWith(busy: false, error: e.message));
    } on Object catch (e) {
      emit(
        state.copyWith(busy: false, error: 'The photo was not uploaded: $e'),
      );
    }
  }

  void removePhoto() => edit(
    (AppInfo d) => d.copyWith(developer: d.developer.copyWith(photo: '')),
  );

  /// Publishes the draft.
  ///
  /// Refused while [AppInfoEditorState.problems] is not empty. And where the
  /// draft raises a minimum version, [typedConfirmation] has to be exactly
  /// [confirmationFor] those versions: a checkbox would not do, because this
  /// is the one edit that locks people out of the app, and a slip of a digit
  /// — 10.0.0 for 1.0.0 — locks out everyone.
  Future<void> publish({String typedConfirmation = ''}) async {
    final List<String> problems = state.problems;
    if (problems.isNotEmpty) {
      emit(
        state.copyWith(
          error: 'Not published. ${problems.length} thing(s) to fix first.',
        ),
      );
      return;
    }
    final Map<String, String> raised = state.raised;
    if (raised.isNotEmpty &&
        typedConfirmation.trim() != confirmationFor(raised)) {
      emit(
        state.copyWith(
          error:
              'Not published. Raising a minimum locks out every install '
              'below it; type ${confirmationFor(raised)} to confirm.',
        ),
      );
      return;
    }

    emit(state.copyWith(busy: true));
    try {
      final String commit = await _pages.publishAppInfo(
        state.draft.toJson(),
        message: _messageFor(state.published, state.draft, raised),
      );
      final String bundled = await _writeBundledCopy();
      emit(
        state.copyWith(
          busy: false,
          source: AppInfoSource.published,
          published: state.draft,
          message:
              'Published${commit.isEmpty ? '' : ' ($commit)'}. The app picks it '
              'up on its next launch; Pages can take a minute to serve it. '
              '$bundled',
        ),
      );
    } on AppException catch (e) {
      emit(state.copyWith(busy: false, error: e.message));
    }
  }

  /// Keeps the bundled copy in step with what was just published, and says
  /// what happened in a sentence. Never a failure of the publish: the file is
  /// live either way, and this only saves a copy-and-paste.
  Future<String> _writeBundledCopy() async {
    final File? file = bundledCopy;
    if (file == null) {
      return 'Copy the JSON into assets/data/app.json so that a fresh install '
          'has it too.';
    }
    try {
      await file.writeAsString(json, flush: true);
      return 'Also written to ${file.path} — commit it, so that a fresh '
          'install starts from the same words.';
    } on FileSystemException catch (e) {
      return 'Could not write ${file.path} (${e.message}); copy the JSON into '
          'it by hand.';
    }
  }

  /// The draft as the file that would be published.
  String get json =>
      '${const JsonEncoder.withIndent('  ').convert(state.draft.toJson())}\n';

  static String _messageFor(
    AppInfo before,
    AppInfo after,
    Map<String, String> raised,
  ) {
    final List<String> changed = <String>[
      if (before.about != after.about) 'about',
      if (before.goal != after.goal) 'goal',
      if (before.developer != after.developer) 'developer',
      if (before.update != after.update) 'update rules',
    ];
    final String minimums = raised.isEmpty
        ? ''
        : ' — minimum raised: '
              '${raised.entries.map((MapEntry<String, String> e) => '${e.key} ${e.value}').join(', ')}';
    return 'Publish app.json: '
        '${changed.isEmpty ? 'no change' : changed.join(', ')}$minimums';
  }

  static String _imageTypeFor(String path) =>
      switch (p.extension(path).toLowerCase()) {
        '.png' => 'image/png',
        '.webp' => 'image/webp',
        _ => 'image/jpeg',
      };

  @override
  Future<void> close() {
    _client.close();
    return super.close();
  }
}
