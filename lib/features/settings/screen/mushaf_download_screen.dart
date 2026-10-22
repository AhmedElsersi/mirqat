import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/desktop.dart';
import '../../../core/di/injection.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/state/load_status.dart';
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
      appBar: AppBar(title: Text(LocaleKeys.downloadsWholeTitle.tr())),
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
                // lasts, so it leads; the rest keep their order under it.
                for (final ReciterOffline entry in <ReciterOffline>[
                  ...state.reciters.where((ReciterOffline e) => e.isRunning),
                  ...state.reciters.where((ReciterOffline e) => !e.isRunning),
                ])
                  _ReciterCard(
                    entry: entry,
                    // One run at a time, so a reciter's button stands down
                    // while another's is going: two runs would split one
                    // connection and read as one stalled bar each.
                    blocked: state.anyRunning && !entry.isRunning,
                    cubit: cubit,
                  ),
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

/// One reciter: who they are, how much of them is here, and the one action.
class _ReciterCard extends StatelessWidget {
  const _ReciterCard({
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

    return Padding(
      padding: EdgeInsetsDirectional.only(bottom: 12.h),
      child: AppCard(
        border: entry.isRunning ? colors.primary : null,
        padding: EdgeInsetsDirectional.all(14.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                ReciterAvatar(reciter: reciter, diameter: 40),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        reciter.nameAr,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        LocaleKeys.downloadsWholeOnDevice.tr(
                          args: <String>[
                            pending.onDevice.toLocalisedString(),
                            pending.offered.toLocalisedString(),
                          ],
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      // Whom the recitation is served through, where the
                      // reciter credits a library for it.
                      if (attribution.isNotEmpty)
                        Text(
                          attribution,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                _Action(entry: entry, blocked: blocked, cubit: cubit),
              ],
            ),
            // How much of this reciter is already here, before any run:
            // the count above says it, and the bar shows it.
            if (!entry.isRunning && pending.offered > 0) ...<Widget>[
              SizedBox(height: 12.h),
              ProgressBar(
                value: pending.onDevice / pending.offered,
                height: 5.r,
              ),
            ],
            SizedBox(height: 10.h),
            _Status(entry: entry),
            // The one thing a reader has to know before starting: it needs
            // the app left open.
            if (entry.isRunning) ...<Widget>[
              SizedBox(height: 8.h),
              Text(
                LocaleKeys.downloadsWholeKeepOpen.tr(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
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

    if (run.isRunning) {
      final PackDownload? current = entry.current;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            LocaleKeys.downloadsWholeRunning.tr(
              args: <String>[
                (run.currentSurah ?? 0).toLocalisedString(),
                (run.done + 1).clamp(1, run.total).toLocalisedString(),
                run.total.toLocalisedString(),
              ],
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          SizedBox(height: 6.h),
          // The run's own bar: how far through the queue it is. Determinate
          // from the first surah, because the queue's length is known before
          // a byte is fetched.
          LinearProgressIndicator(value: run.progress, minHeight: 5.h),
          if (current != null && current.isBusy) ...<Widget>[
            SizedBox(height: 4.h),
            // The surah being fetched, under the run. Indeterminate while
            // hashing and unzipping, which have no percentage to report.
            LinearProgressIndicator(
              value:
                  current.status == PackStatus.downloading &&
                      current.progress > 0
                  ? current.progress
                  : null,
              minHeight: 2.h,
              backgroundColor: colors.surfaceContainerHighest,
            ),
          ],
        ],
      );
    }

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
        colors.onSurfaceVariant,
      ),
      BulkStatus.finished => (
        LocaleKeys.downloadsWholeFinished.tr(
          args: <String>[run.done.toLocalisedString()],
        ),
        colors.onSurfaceVariant,
      ),
      BulkStatus.idle ||
      BulkStatus.running => (_remaining(pending), colors.onSurfaceVariant),
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
              _remaining(pending),
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
  static String _remaining(PendingDownloads pending) {
    if (pending.isComplete) return LocaleKeys.downloadsWholeComplete.tr();
    final String count = pending.surahs.length.toLocalisedString();
    return pending.bytes > 0
        ? LocaleKeys.downloadsWholeRemaining.tr(
            args: <String>[count, megabytes(pending.bytes)],
          )
        : LocaleKeys.downloadsWholeRemainingUnsized.tr(args: <String>[count]);
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
    if (entry.isRunning) {
      return IconButton(
        onPressed: () => cubit.cancel(entry.reciter),
        tooltip: LocaleKeys.commonCancel.tr(),
        icon: const Icon(Icons.stop_circle_outlined),
      );
    }
    if (entry.isComplete) {
      return Icon(
        Icons.offline_pin_outlined,
        color: Theme.of(context).colorScheme.primary,
      );
    }
    return IconButton(
      onPressed: blocked ? null : () => _confirm(context),
      tooltip: LocaleKeys.downloadsWholeDownload.tr(),
      icon: const Icon(Icons.download_for_offline_outlined),
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
