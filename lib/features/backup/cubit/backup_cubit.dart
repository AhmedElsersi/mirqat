import 'package:dartz/dartz.dart' hide State;
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failures.dart';
import '../../../services/backup_service.dart';

class BackupState extends Equatable {
  const BackupState({
    this.folder,
    this.files = const <BackupFile>[],
    this.busy = false,
    this.exportedTo,
    this.merged,
    this.refusal,
    this.failed = false,
  });

  /// Where backups are written and read from.
  final String? folder;
  final List<BackupFile> files;
  final bool busy;

  /// The file just written.
  final String? exportedTo;

  /// What the last import changed.
  final BackupMerge? merged;

  /// Why the last import was refused.
  final BackupRefusal? refusal;

  /// The last export could not be written.
  final bool failed;

  @override
  List<Object?> get props => <Object?>[
    folder,
    files,
    busy,
    exportedTo,
    merged,
    refusal,
    failed,
  ];
}

class BackupCubit extends Cubit<BackupState> {
  BackupCubit({required BackupService backupService})
    : _backup = backupService,
      super(const BackupState());

  final BackupService _backup;

  Future<void> load() async {
    final String? folder = await _backup.folder();
    final List<BackupFile> files = await _backup.list();
    if (!isClosed) emit(BackupState(folder: folder, files: files));
  }

  Future<void> export() async {
    emit(BackupState(folder: state.folder, files: state.files, busy: true));
    final Either<Failure, String> result = await _backup.export();
    final List<BackupFile> files = await _backup.list();
    if (isClosed) return;
    emit(
      BackupState(
        folder: state.folder,
        files: files,
        exportedTo: result.fold((_) => null, (String path) => path),
        failed: result.isLeft(),
      ),
    );
  }

  Future<void> import(BackupFile file) async {
    emit(BackupState(folder: state.folder, files: state.files, busy: true));
    final Either<BackupRefusal, BackupMerge> result = await _backup.import(
      file.path,
    );
    if (isClosed) return;
    emit(
      BackupState(
        folder: state.folder,
        files: state.files,
        merged: result.fold((_) => null, (BackupMerge m) => m),
        refusal: result.fold((BackupRefusal r) => r, (_) => null),
      ),
    );
  }
}
