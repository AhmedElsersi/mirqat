import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/desktop.dart';
import '../../../core/di/injection.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/panel.dart';
import '../../../services/backup_service.dart';
import '../cubit/backup_cubit.dart';

/// The reader's progress, saved to a file and taken back in — to move to a
/// new phone, or to keep somewhere safe. No account: the file is theirs.
///
/// What a copy holds is four tags rather than a paragraph, and the path is
/// set latin and read from the left, whatever the interface language.
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
              padding: EdgeInsetsDirectional.fromSTEB(16.w, 12.h, 16.w, 32.h),
              children: <Widget>[
                AppCard(
                  padding: EdgeInsetsDirectional.all(16.r),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const TileIcon(Icons.save_alt),
                          SizedBox(width: 12.w),
                          Expanded(
                            child: Text(
                              LocaleKeys.backupNoAccount.tr(),
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 14.h),
                      Wrap(
                        spacing: 8.w,
                        runSpacing: 8.h,
                        children: <Widget>[
                          AppTag(label: LocaleKeys.backupHoldsProgress.tr()),
                          AppTag(label: LocaleKeys.backupHoldsReviews.tr()),
                          AppTag(label: LocaleKeys.backupHoldsWeakSpots.tr()),
                          AppTag(label: LocaleKeys.backupHoldsPlan.tr()),
                        ],
                      ),
                    ],
                  ),
                ),

                FieldLabel(LocaleKeys.backupExport.tr()),
                AppCard(
                  padding: EdgeInsetsDirectional.all(16.r),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: Size(0, 48.r),
                        ),
                        onPressed: state.busy ? null : cubit.export,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(LocaleKeys.backupExportNow.tr()),
                      ),
                      if (state.exportedTo != null) ...<Widget>[
                        SizedBox(height: 12.h),
                        Text(
                          LocaleKeys.backupSavedAt.tr(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        SizedBox(height: 6.h),
                        _Path(path: state.exportedTo!),
                        if (cubit.canShare) ...<Widget>[
                          SizedBox(height: 10.h),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: ActionChip(
                              avatar: const Icon(Icons.share_outlined),
                              onPressed: cubit.shareExported,
                              label: Text(LocaleKeys.backupShare.tr()),
                            ),
                          ),
                        ],
                      ],
                      if (state.failed) ...<Widget>[
                        SizedBox(height: 8.h),
                        Text(
                          LocaleKeys.backupExportFailed.tr(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                FieldLabel(LocaleKeys.backupImport.tr()),
                AppCard(
                  padding: EdgeInsetsDirectional.all(16.r),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (cubit.canPick) ...<Widget>[
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: Size(0, 48.r),
                          ),
                          onPressed: state.busy
                              ? null
                              : () => _confirmPick(context, cubit),
                          icon: const Icon(Icons.folder_open_outlined),
                          label: Text(LocaleKeys.backupPick.tr()),
                        ),
                        SizedBox(height: 8.h),
                        Text(
                          LocaleKeys.backupPickHint.tr(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        SizedBox(height: 12.h),
                      ],
                      if (state.files.isEmpty)
                        Text(
                          LocaleKeys.backupNone.tr(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                      else
                        // The copies found, as rows of a list in the card:
                        // the file, when it was made, and the one action.
                        AppCard(
                          padding: EdgeInsetsDirectional.zero,
                          child: Column(
                            children: <Widget>[
                              for (final BackupFile f
                                  in state.files) ...<Widget>[
                                if (f != state.files.first)
                                  const Divider(height: 1),
                                ListTile(
                                  contentPadding:
                                      EdgeInsetsDirectional.fromSTEB(
                                        12.w,
                                        4.h,
                                        12.w,
                                        4.h,
                                      ),
                                  leading: const TileIcon(Icons.data_object),
                                  title: Text(
                                    f.name,
                                    textDirection: TextDirection.ltr,
                                    textAlign: TextAlign.start,
                                    style: theme.textTheme.titleSmall,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    joinDetails(<String>[
                                      DateFormat.yMMMMd(
                                            context.locale.toString(),
                                          )
                                          .format(f.modified)
                                          .withLocalisedDigits(),
                                      if (f.bytes > 0)
                                        LocaleKeys.backupSizeKb.tr(
                                          args: <String>[
                                            (f.bytes / 1024)
                                                .ceil()
                                                .toLocalisedString(),
                                          ],
                                        ),
                                    ]),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  trailing: ActionChip(
                                    label: Text(
                                      LocaleKeys.backupImportThis.tr(),
                                    ),
                                    onPressed: state.busy
                                        ? null
                                        : () =>
                                              _confirmImport(context, cubit, f),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      SizedBox(height: 12.h),
                      // What an import does, before one is chosen: it merges,
                      // and nothing is lost.
                      AppNote(
                        LocaleKeys.backupMergeNote.tr(),
                        icon: Icons.merge_outlined,
                      ),
                      SizedBox(height: 8.h),
                      // Said because it loses data: Android removes the app's
                      // folder, and every copy in it, with the app.
                      AppNote(
                        LocaleKeys.backupWhere.tr(),
                        icon: Icons.warning_amber_outlined,
                      ),
                      if (state.refusal != null) ...<Widget>[
                        SizedBox(height: 10.h),
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
                    ],
                  ),
                ),

                if (state.merged != null) ...<Widget>[
                  SizedBox(height: 12.h),
                  _Merged(merge: state.merged!),
                ],
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

/// A path: latin, read from the left, and selectable — it is often typed
/// into something else.
class _Path extends StatelessWidget {
  const _Path({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsetsDirectional.all(10.r),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: SelectableText(
        path,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

/// What an import took in, said once it has happened.
class _Merged extends StatelessWidget {
  const _Merged({required this.merge});

  final BackupMerge merge;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color done = theme.brightness == Brightness.dark
        ? AppColors.sabrDark
        : AppColors.sabrLight;
    return AppCard(
      padding: EdgeInsetsDirectional.all(16.r),
      child: Row(
        children: <Widget>[
          Icon(Icons.check_circle_outline, color: done),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              LocaleKeys.backupMerged.tr(
                args: <String>[
                  merge.ayahs.toLocalisedString(),
                  merge.reviews.toLocalisedString(),
                  merge.days.toLocalisedString(),
                ],
              ),
              style: theme.textTheme.bodyMedium?.copyWith(color: done),
            ),
          ),
        ],
      ),
    );
  }
}
