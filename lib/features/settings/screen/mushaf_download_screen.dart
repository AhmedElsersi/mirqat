import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/desktop.dart';
import '../../../core/di/injection.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/state/load_status.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/panel.dart';
import '../../../core/widgets/reciter_avatar.dart';
import '../../../data/models/audio_pack.dart';
import '../../../data/models/reciter.dart';
import '../cubit/mushaf_download_cubit.dart';
import '../cubit/mushaf_download_state.dart';
import 'downloads_screen.dart' show megabytes;

/// The whole mushaf, for one reciter, in one action.
///
/// Downloading a surah at a time from the reader is right for memorizing one;
/// it is the wrong way to prepare for a journey with no signal. This screen
/// is the other way round: a reciter, and everything they have recited.
///
/// It offers nothing the per-surah control does not — the same service, the
/// same verification, the same rows — so nothing here is a gate: every surah
/// stays readable, and an undownloaded one still streams.
class MushafDownloadScreen extends StatelessWidget {
  const MushafDownloadScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider<MushafDownloadCubit>(
    create: (_) => sl<MushafDownloadCubit>()..load(),
    child: Scaffold(
      appBar: AppBar(title: Text(LocaleKeys.downloadsWholeScreenTitle.tr())),
      body: BlocBuilder<MushafDownloadCubit, MushafDownloadState>(
        builder: (BuildContext context, MushafDownloadState state) {
          if (state.status.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final MushafDownloadCubit cubit = context.read<MushafDownloadCubit>();
          final ThemeData theme = Theme.of(context);

          return DesktopWidth(
            child: ListView(
              padding: EdgeInsetsDirectional.all(16.r),
              children: <Widget>[
                Text(
                  LocaleKeys.downloadsWholeIntro.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: 16.h),
                if (state.reciters.isEmpty)
                  Text(
                    LocaleKeys.downloadsWholeNone.tr(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                // A run under way is what the screen is about while it
                // lasts, so it leads as a card; the rest are rows under it.
                for (final ReciterOffline entry in state.reciters.where(
                  (ReciterOffline e) => e.isRunning,
                ))
                  _RunningCard(
                    entry: entry,
                    cubit: cubit,
                    surahNames: state.surahNames,
                  ),
                if (state.reciters.any(
                  (ReciterOffline e) => !e.isRunning,
                )) ...<Widget>[
                  FieldLabel(
                    state.anyRunning
                        ? LocaleKeys.downloadsWholeOthers.tr()
                        : LocaleKeys.downloadsWholeReciters.tr(),
                  ),
                  AppCard(
                    padding: EdgeInsetsDirectional.zero,
                    child: Column(
                      children: <Widget>[
                        for (final ReciterOffline entry in state.reciters.where(
                          (ReciterOffline e) => !e.isRunning,
                        )) ...<Widget>[
                          if (entry !=
                              state.reciters.firstWhere(
                                (ReciterOffline e) => !e.isRunning,
                              ))
                            const Divider(height: 1),
                          _ReciterRow(
                            entry: entry,
                            // One run at a time, so a reciter's button
                            // stands down while another's is going: two
                            // runs would split one connection and read as
                            // one stalled bar each.
                            blocked: state.anyRunning,
                            cubit: cubit,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                if (state.errorMessage != null)
                  Padding(
                    padding: EdgeInsetsDirectional.only(top: 8.h),
                    child: Text(
                      state.errorMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

/// The run under way: whose, which surah, how far the whole has got and how
/// far this surah has, and the one way to stop it.
class _RunningCard extends StatelessWidget {
  const _RunningCard({
    required this.entry,
    required this.cubit,
    required this.surahNames,
  });

  final ReciterOffline entry;
  final MushafDownloadCubit cubit;
  final Map<int, String> surahNames;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final BulkDownload run = entry.run;
    final PackDownload? current = entry.current;
    final Color sabr = theme.brightness == Brightness.dark
        ? AppColors.sabrDark
        : AppColors.sabrLight;

    return Padding(
      padding: EdgeInsetsDirectional.only(bottom: 4.h),
      child: AppCard(
        border: colors.primary,
        padding: EdgeInsetsDirectional.all(16.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                ReciterAvatar(reciter: entry.reciter, diameter: 44),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        entry.reciter.nameAr,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        LocaleKeys.downloadsWholeRunning.tr(
                          args: <String>[
                            surahNames[run.currentSurah] ??
                                (run.currentSurah ?? 0).toLocalisedString(),
                            (run.done + 1)
                                .clamp(1, run.total)
                                .toLocalisedString(),
                            run.total.toLocalisedString(),
                          ],
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton.outlined(
                  onPressed: () => cubit.cancel(entry.reciter),
                  tooltip: LocaleKeys.downloadsWholeStop.tr(),
                  icon: const Icon(Icons.stop_rounded),
                ),
              ],
            ),
            SizedBox(height: 14.h),
            // The run's own bar: how far through the queue it is —
            // determinate from the first surah, because the queue's length
            // is known before a byte is fetched. Under it, the surah being
            // fetched; indeterminate while hashing and unzipping.
            ProgressBar(value: run.progress),
            if (current != null && current.isBusy) ...<Widget>[
              SizedBox(height: 6.h),
              ClipRRect(
                borderRadius: BorderRadius.circular(2.r),
                child: LinearProgressIndicator(
                  value:
                      current.status == PackStatus.downloading &&
                          current.progress > 0
                      ? current.progress
                      : null,
                  minHeight: 4.r,
                  color: sabr,
                  backgroundColor: colors.surfaceContainerHighest,
                ),
              ),
            ],
            SizedBox(height: 10.h),
            // The one thing a reader has to know: it needs the app left open.
            AppNote(LocaleKeys.downloadsWholeKeepOpen.tr()),
          ],
        ),
      ),
    );
  }
}

/// A reciter not being fetched now: who they are, how much of them is here,
/// and the one action.
class _ReciterRow extends StatelessWidget {
  const _ReciterRow({
    required this.entry,
    required this.blocked,
    required this.cubit,
  });

  final ReciterOffline entry;
  final bool blocked;
  final MushafDownloadCubit cubit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final Reciter reciter = entry.reciter;
    final PendingDownloads pending = entry.pending;
    final String attribution = reciter.attribution.of(
      context.locale.languageCode,
    );
    return ListTile(
      contentPadding: EdgeInsetsDirectional.fromSTEB(14.w, 8.h, 10.w, 8.h),
      leading: ReciterAvatar(reciter: reciter, diameter: 40),
      title: Text(
        reciter.nameAr,
        style: theme.textTheme.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Status(entry: entry),
          // Whom the recitation is served through, where the reciter
          // credits a library for it.
          if (attribution.isNotEmpty)
            Text(
              attribution,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          // How much of this reciter is already here, where some is.
          if (!entry.isComplete &&
              pending.offered > 0 &&
              pending.onDevice > 0) ...<Widget>[
            SizedBox(height: 8.h),
            ProgressBar(value: pending.onDevice / pending.offered),
          ],
        ],
      ),
      trailing: _Action(entry: entry, blocked: blocked, cubit: cubit),
    );
  }
}

/// What this reciter's row has to say: what is left, or how the run is
/// getting on, or how it ended.
class _Status extends StatelessWidget {
  const _Status({required this.entry});

  final ReciterOffline entry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final BulkDownload run = entry.run;
    final PendingDownloads pending = entry.pending;

    final (String text, Color colour) = switch (run.status) {
      BulkStatus.cancelled => (
        LocaleKeys.downloadsWholeCancelled.tr(),
        colors.onSurfaceVariant,
      ),
      BulkStatus.finished when run.failed.isNotEmpty => (
        LocaleKeys.downloadsWholeRunFailed.tr(
          args: <String>[run.failed.length.toLocalisedString()],
        ),
        colors.error,
      ),
      BulkStatus.finished when pending.isComplete => (
        LocaleKeys.downloadsWholeComplete.tr(),
        theme.brightness == Brightness.dark
            ? AppColors.sabrDark
            : AppColors.sabrLight,
      ),
      BulkStatus.finished => (
        LocaleKeys.downloadsWholeFinished.tr(
          args: <String>[run.done.toLocalisedString()],
        ),
        colors.onSurfaceVariant,
      ),
      BulkStatus.idle || BulkStatus.running => (
        _remaining(entry),
        pending.isComplete
            ? (theme.brightness == Brightness.dark
                  ? AppColors.sabrDark
                  : AppColors.sabrLight)
            : colors.onSurfaceVariant,
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(text, style: theme.textTheme.bodySmall?.copyWith(color: colour)),
        // Said again after a run that ended with failures: what is still
        // missing is the thing a second run would fetch.
        if (!pending.isComplete && run.status != BulkStatus.idle)
          Padding(
            padding: EdgeInsetsDirectional.only(top: 2.h),
            child: Text(
              _remaining(entry),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  /// What is left to fetch — with a size where the manifest gives one, and
  /// without where it does not. A reciter published without packs has no
  /// sizes to add up, and a figure is never guessed.
  ///
  /// One line: how much of the reciter is here and what is left where some
  /// is; their bitrate and the whole cost where none is yet.
  static String _remaining(ReciterOffline entry) {
    final PendingDownloads pending = entry.pending;
    if (pending.isComplete) return LocaleKeys.downloadsWholeComplete.tr();
    final String count = pending.surahs.length.toLocalisedString();
    final int? bitrate = entry.reciter.remote?.bitrate;
    return joinDetails(<String>[
      if (pending.onDevice > 0)
        LocaleKeys.downloadsWholeOnDevice.tr(
          args: <String>[
            pending.onDevice.toLocalisedString(),
            pending.offered.toLocalisedString(),
          ],
        )
      else if (bitrate != null && bitrate > 0)
        LocaleKeys.downloadsBitrate.tr(
          args: <String>[bitrate.toLocalisedString()],
        ),
      if (pending.bytes <= 0)
        LocaleKeys.downloadsWholeRemainingUnsized.tr(args: <String>[count])
      else if (pending.onDevice > 0)
        LocaleKeys.downloadsWholeRemaining.tr(
          args: <String>[megabytes(pending.bytes)],
        )
      else
        LocaleKeys.downloadsWholeAboutSize.tr(
          args: <String>[megabytes(pending.bytes)],
        ),
    ]);
  }
}

/// Download everything, or stop. Nothing else: freeing what was downloaded
/// belongs to the saved-recitations screen, which is where the sizes are.
class _Action extends StatelessWidget {
  const _Action({
    required this.entry,
    required this.blocked,
    required this.cubit,
  });

  final ReciterOffline entry;
  final bool blocked;
  final MushafDownloadCubit cubit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (entry.isRunning) {
      return IconButton.outlined(
        onPressed: () => cubit.cancel(entry.reciter),
        tooltip: LocaleKeys.downloadsWholeStop.tr(),
        icon: const Icon(Icons.stop_rounded),
      );
    }
    if (entry.isComplete) {
      return Icon(
        Icons.check_circle_outline,
        color: theme.brightness == Brightness.dark
            ? AppColors.sabrDark
            : AppColors.sabrLight,
      );
    }
    return IconButton.outlined(
      onPressed: blocked ? null : () => _confirm(context),
      tooltip: LocaleKeys.downloadsWholeDownload.tr(),
      icon: const Icon(Icons.download_outlined),
    );
  }

  /// Asked before it starts, and the size is in the question.
  ///
  /// A whole mushaf is hundreds of megabytes and an hour of someone's data
  /// plan; the per-surah button needs no confirmation because a surah is tens
  /// of megabytes, and this is not that.
  Future<void> _confirm(BuildContext context) async {
    final PendingDownloads pending = entry.pending;
    final String count = pending.surahs.length.toLocalisedString();
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(LocaleKeys.downloadsWholeConfirmTitle.tr()),
        content: Text(
          pending.bytes > 0
              ? LocaleKeys.downloadsWholeConfirmBody.tr(
                  args: <String>[
                    count,
                    entry.reciter.nameAr,
                    megabytes(pending.bytes),
                  ],
                )
              : LocaleKeys.downloadsWholeConfirmBodyUnsized.tr(
                  args: <String>[count, entry.reciter.nameAr],
                ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(LocaleKeys.commonCancel.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(LocaleKeys.downloadsWholeConfirmCta.tr()),
          ),
        ],
      ),
    );
    if (go ?? false) await cubit.downloadWhole(entry.reciter);
  }
}
