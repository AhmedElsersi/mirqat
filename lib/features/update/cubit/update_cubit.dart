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
    this.target = '',
    this.notes = LocalizedText.empty,
    this.maintenance,
    this.retrying = false,
  });

  final UpdateKind kind;
  final String storeUrl;
  final String latest;

  /// The release the prompt asks for, as a label — `1.2.0 (25)`.
  final String target;
  final LocalizedText notes;

  /// The closed sign, when it is up for this platform right now. Shown over
  /// everything, ahead of any update prompt.
  final Maintenance? maintenance;

  /// Asking the site again, from the maintenance page.
  final bool retrying;

  bool get underMaintenance => maintenance != null;

  @override
  List<Object?> get props => <Object?>[
    kind,
    storeUrl,
    latest,
    target,
    notes,
    maintenance,
    retrying,
  ];
}

/// Whether to say anything about updating — or that the app is closed for
/// maintenance — for this platform and this install. App-wide: the prompt
/// sits over whatever screen is up.
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

  /// The platform as `app.json` names it. No store, no update rules for the
  /// desktop builds — the macOS build is the admin tool, the Windows build a
  /// zip handed out by hand — but a maintenance sign with no platforms named
  /// is up for them too.
  String get _platformName => switch (_platform ?? defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    TargetPlatform.macOS => 'macos',
    TargetPlatform.windows => 'windows',
    TargetPlatform.linux => 'linux',
    TargetPlatform.fuchsia => 'fuchsia',
  };

  Future<void> _evaluate(AppInfo info) async {
    if (isClosed) return;
    final DateTime now = _now();
    // The closed sign comes first: it needs no version to be read, and it
    // says more than any update prompt could while it is up.
    if (info.maintenance.isActive(platform: _platformName, now: now)) {
      emit(UpdateState(maintenance: info.maintenance));
      return;
    }

    final InstalledVersion? installed = await _version.read();
    if (isClosed) return;
    if (installed == null) {
      emit(const UpdateState());
      return;
    }
    final PlatformUpdate rules = info.update.forPlatform(_platformName);
    final UpdateKind kind = decideUpdate(
      installed: installed.version,
      installedBuild: installed.buildNumber,
      rules: rules,
      lastPrompted: _lastPrompted,
      now: now,
      remindAfter: Duration(days: info.update.remindAfterDays),
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
              target: rules.target,
              notes: info.update.notes,
            ),
    );
  }

  /// From the maintenance page: ask the site again, now. A sign that has
  /// been taken down comes down here without a restart.
  Future<void> retry() async {
    if (state.retrying) return;
    emit(UpdateState(maintenance: state.maintenance, retrying: true));
    final AppInfo info = await _info.refresh();
    if (isClosed) return;
    await _evaluate(info);
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
