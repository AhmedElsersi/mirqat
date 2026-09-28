import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/app_info.dart';
import '../../../services/app_info_service.dart';
import '../../../services/app_version_service.dart';
import '../../../services/update_policy.dart';

class UpdateState extends Equatable {
  const UpdateState({
    this.kind = UpdateKind.none,
    this.storeUrl = '',
    this.latest = '',
    this.notes = LocalizedText.empty,
  });

  final UpdateKind kind;
  final String storeUrl;
  final String latest;
  final LocalizedText notes;

  @override
  List<Object?> get props => <Object?>[kind, storeUrl, latest, notes];
}

/// Whether to say anything about updating, for this platform and this
/// install. App-wide: the prompt sits over whatever screen is up.
class UpdateCubit extends Cubit<UpdateState> {
  UpdateCubit({
    required AppInfoService appInfoService,
    required AppVersionService appVersionService,
    TargetPlatform? platformOverride,
    DateTime Function() clock = DateTime.now,
  }) : _info = appInfoService,
       _version = appVersionService,
       _platform = platformOverride,
       _now = clock,
       super(const UpdateState());

  final AppInfoService _info;
  final AppVersionService _version;
  final TargetPlatform? _platform;
  final DateTime Function() _now;

  StreamSubscription<AppInfo>? _changes;
  DateTime? _lastPrompted;
  bool _dismissed = false;

  /// Looks once with what is on the device, and again whenever a newer
  /// `app.json` arrives — so a rule published while the app is open is heard
  /// in that same run. [lastPrompted] is when an optional update was last
  /// mentioned, from the stored settings.
  Future<void> check({required DateTime? lastPrompted}) async {
    _lastPrompted = lastPrompted;
    _changes ??= _info.changes.listen(_evaluate);
    await _evaluate(await _info.load());
  }

  Future<void> _evaluate(AppInfo info) async {
    final InstalledVersion? installed = await _version.read();
    if (isClosed || installed == null) return;

    final PlatformUpdate rules = switch (_platform ?? defaultTargetPlatform) {
      TargetPlatform.android => info.update.android,
      TargetPlatform.iOS => info.update.ios,
      // No store, no rules: the macOS build is the admin tool, and the
      // Windows build is a zip handed out by hand.
      _ => PlatformUpdate.none,
    };
    final UpdateKind kind = decideUpdate(
      installed: installed.version,
      rules: rules,
      lastPrompted: _lastPrompted,
      now: _now(),
    );
    // "Later" holds for the rest of this run, whatever arrives — but it was
    // only ever an answer to an update that could wait.
    if (_dismissed && kind == UpdateKind.optional) return;

    emit(
      kind == UpdateKind.none
          ? const UpdateState()
          : UpdateState(
              kind: kind,
              storeUrl: rules.storeUrl,
              latest: rules.latest,
              notes: info.update.notes,
            ),
    );
  }

  /// "Later". Only an optional update can be put off.
  void dismiss() {
    if (state.kind != UpdateKind.optional) return;
    _dismissed = true;
    _lastPrompted = _now();
    emit(const UpdateState());
  }

  @override
  Future<void> close() async {
    await _changes?.cancel();
    return super.close();
  }
}
