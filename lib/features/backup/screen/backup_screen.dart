import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/desktop.dart';
import '../../../core/di/injection.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/widgets/settings_card.dart';
import '../../../services/backup_service.dart';
import '../cubit/backup_cubit.dart';

/// The reader's progress, saved to a file and taken back in — to move to a
/// new phone, or to keep somewhere safe. No account: the file is theirs.
class BackupScreen extends StatelessWidget {
  const BackupScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider<BackupCubit>(
    create: (_) => sl<BackupCubit>()..load(),
    child: Scaffold(
      appBar: AppBar(title: Text(LocaleKeys.backupTitle.tr())),
      body: DesktopWidth(
        child: BlocBuilder<BackupCubit, BackupState>(
          builder: (BuildContext context, BackupState state) {
            final ThemeData theme = Theme.of(context);
            final BackupCubit cubit = context.read<BackupCubit>();
            return ListView(
              padding: EdgeInsetsDirectional.all(16.r),
              children: <Widget>[
                Text(
                  LocaleKeys.backupIntro.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: 16.h),
                SettingsCard(
                  title: LocaleKeys.backupExport.tr(),
                  icon: Icons.upload_file_outlined,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: state.busy ? null : cubit.export,
                      icon: const Icon(Icons.save_alt),
                      label: Text(LocaleKeys.backupExportNow.tr()),
                    ),
                    if (state.exportedTo != null) ...<Widget>[
                      SizedBox(height: 8.h),
                      Text(LocaleKeys.backupSavedAt.tr()),
                      SelectableText(
                        state.exportedTo!,
                        textDirection: TextDirection.ltr,
                        style: theme.textTheme.bodySmall,
                      ),
                      if (cubit.canShare) ...<Widget>[
                        SizedBox(height: 8.h),
                        OutlinedButton.icon(
                          onPressed: cubit.shareExported,
                          icon: const Icon(Icons.ios_share),
                          label: Text(LocaleKeys.backupShare.tr()),
                        ),
                      ],
                    ],
                    if (state.failed)
                      Text(
                        LocaleKeys.backupExportFailed.tr(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                  ],
                ),
                SettingsCard(
                  title: LocaleKeys.backupImport.tr(),
                  icon: Icons.download_outlined,
                  children: <Widget>[
                    if (cubit.canPick) ...<Widget>[
                      FilledButton.icon(
                        onPressed: state.busy
                            ? null
                            : () => _confirmPick(context, cubit),
                        icon: const Icon(Icons.file_open_outlined),
                        label: Text(LocaleKeys.backupPick.tr()),
                      ),
                      Text(
                        LocaleKeys.backupPickHint.tr(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      SizedBox(height: 12.h),
                    ],
                    Text(
                      LocaleKeys.backupWhere.tr(),
                      style: theme.textTheme.bodySmall,
                    ),
                    if (state.folder != null)
                      SelectableText(
                        state.folder!,
                        textDirection: TextDirection.ltr,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    SizedBox(height: 8.h),
                    if (state.files.isEmpty)
                      Text(
                        LocaleKeys.backupNone.tr(),
                        style: theme.textTheme.bodySmall,
                      )
                    else
                      for (final BackupFile f in state.files)
                        ListTile(
                          contentPadding: EdgeInsetsDirectional.zero,
                          leading: const Icon(Icons.description_outlined),
                          title: Text(f.name, textDirection: TextDirection.ltr),
                          trailing: TextButton(
                            onPressed: state.busy
                                ? null
                                : () => _confirmImport(context, cubit, f),
                            child: Text(LocaleKeys.backupImportThis.tr()),
                          ),
                        ),
                    TextButton.icon(
                      onPressed: state.busy ? null : cubit.load,
                      icon: const Icon(Icons.refresh),
                      label: Text(LocaleKeys.backupRefresh.tr()),
                    ),
                    if (state.merged != null) _Merged(merge: state.merged!),
                    if (state.refusal != null)
                      Text(
                        switch (state.refusal!) {
                          BackupRefusal.notABackup =>
                            LocaleKeys.backupNotABackup.tr(),
                          BackupRefusal.newerVersion =>
                            LocaleKeys.backupNewer.tr(),
                          BackupRefusal.unreadable =>
                            LocaleKeys.backupUnreadable.tr(),
                        },
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  /// The same promise as importing from the folder, asked first: nothing on
  /// this device is removed.
  static Future<void> _confirmPick(
    BuildContext context,
    BackupCubit cubit,
  ) async {
    if (await _confirm(context)) await cubit.importPicked();
  }

  static Future<bool> _confirm(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        builder: (BuildContext dialog) => AlertDialog(
          content: Text(LocaleKeys.backupImportConfirm.tr()),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(false),
              child: Text(LocaleKeys.commonCancel.tr()),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialog).pop(true),
              child: Text(LocaleKeys.backupImportThis.tr()),
            ),
          ],
        ),
      ) ??
      false;

  static Future<void> _confirmImport(
    BuildContext context,
    BackupCubit cubit,
    BackupFile file,
  ) async {
    if (await _confirm(context)) await cubit.import(file);
  }
}

class _Merged extends StatelessWidget {
  const _Merged({required this.merge});

  final BackupMerge merge;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsetsDirectional.only(top: 8.h),
    child: Text(
      LocaleKeys.backupMerged.tr(
        args: <String>[
          merge.ayahs.toLocalisedString(),
          merge.reviews.toLocalisedString(),
          merge.days.toLocalisedString(),
        ],
      ),
      style: Theme.of(context).textTheme.bodyMedium,
    ),
  );
}
