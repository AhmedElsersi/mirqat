import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/di/injection.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/state/load_status.dart';
import '../../../data/models/audio_pack.dart';
import '../cubit/downloads_cubit.dart';
import '../cubit/downloads_state.dart';

/// What is saved for offline listening, and what it costs.
///
/// A surah can be downloaded from the reader's session settings, where the
/// surah is already in front of the reader. It can only be *freed* from there
/// too, which is fine while there is one — this screen is for the day there
/// are thirty.
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider<DownloadsCubit>(
    create: (_) => sl<DownloadsCubit>()..load(),
    child: Scaffold(
      appBar: AppBar(title: Text(LocaleKeys.downloadsSavedTitle.tr())),
      body: BlocBuilder<DownloadsCubit, DownloadsState>(
        builder: (BuildContext context, DownloadsState state) {
          if (state.status.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          final DownloadsCubit cubit = context.read<DownloadsCubit>();

          if (state.saved.isEmpty && state.failed.isEmpty) {
            return _Empty(message: state.errorMessage);
          }

          final Map<String, List<SavedRecitation>> grouped = state.byReciter;

          return ListView(
            padding: EdgeInsetsDirectional.all(16.r),
            children: <Widget>[
              if (state.busy)
                Padding(
                  padding: EdgeInsetsDirectional.only(bottom: 12.h),
                  child: const LinearProgressIndicator(),
                ),
              for (final MapEntry<String, List<SavedRecitation>> entry
                  in grouped.entries)
                _ReciterGroup(
                  reciterId: entry.key,
                  items: entry.value,
                  cubit: cubit,
                  busy: state.busy,
                ),
              if (state.failed.isNotEmpty)
                _FailedGroup(
                  items: state.failed,
                  cubit: cubit,
                  busy: state.busy,
                ),
              const Divider(height: 1),
              _Total(bytes: state.totalBytes, error: state.errorMessage),
            ],
          );
        },
      ),
    ),
  );
}

/// One reciter's saved surahs, with the two actions that apply to all of
/// them.
class _ReciterGroup extends StatelessWidget {
  const _ReciterGroup({
    required this.reciterId,
    required this.items,
    required this.cubit,
    required this.busy,
  });

  final String reciterId;
  final List<SavedRecitation> items;
  final DownloadsCubit cubit;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String name = items.first.reciter?.nameAr ?? reciterId;
    final bool hasStale = items.any((SavedRecitation s) => s.pack.isStale);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: EdgeInsetsDirectional.only(top: 8.h, bottom: 4.h),
          child: Text(name, style: theme.textTheme.titleSmall),
        ),
        for (final SavedRecitation saved in items)
          _SavedRow(saved: saved, cubit: cubit),
        Row(
          children: <Widget>[
            if (hasStale)
              TextButton.icon(
                onPressed: busy ? null : () => cubit.redownloadStale(reciterId),
                icon: const Icon(Icons.refresh),
                label: Text(LocaleKeys.downloadsRedownloadReciter.tr()),
              ),
            const Spacer(),
            TextButton.icon(
              onPressed: busy ? null : () => cubit.deleteReciter(reciterId),
              icon: const Icon(Icons.delete_sweep_outlined),
              label: Text(LocaleKeys.downloadsDeleteReciter.tr()),
            ),
          ],
        ),
        SizedBox(height: 8.h),
      ],
    );
  }
}

/// Downloads that were asked for and did not arrive.
class _FailedGroup extends StatelessWidget {
  const _FailedGroup({
    required this.items,
    required this.cubit,
    required this.busy,
  });

  final List<SavedRecitation> items;
  final DownloadsCubit cubit;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: EdgeInsetsDirectional.only(top: 8.h, bottom: 4.h),
          child: Text(
            LocaleKeys.downloadsFailedRow.tr(),
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
        for (final SavedRecitation saved in items)
          ListTile(
            contentPadding: EdgeInsetsDirectional.zero,
            leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
            title: Text(
              saved.surah?.nameAr ?? saved.pack.surahNumber.toLocalisedString(),
            ),
            subtitle: Text(saved.reciter?.nameAr ?? saved.pack.reciterId),
            trailing: IconButton(
              onPressed: busy ? null : () => cubit.delete(saved),
              tooltip: LocaleKeys.downloadsDelete.tr(),
              icon: const Icon(Icons.close),
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: busy ? null : cubit.retryFailed,
            icon: const Icon(Icons.refresh),
            label: Text(
              LocaleKeys.downloadsRetryFailed.tr(
                args: <String>[items.length.toLocalisedString()],
              ),
            ),
          ),
        ),
        SizedBox(height: 8.h),
      ],
    );
  }
}

class _SavedRow extends StatelessWidget {
  const _SavedRow({required this.saved, required this.cubit});

  final SavedRecitation saved;
  final DownloadsCubit cubit;

  @override
  Widget build(BuildContext context) {
    final InstalledPack pack = saved.pack;
    // A surah or reciter the catalog no longer knows still has to name itself,
    // or the row would be an anonymous delete button.
    final String surahName =
        saved.surah?.nameAr ??
        LocaleKeys.commonAyahNumber.tr(
          args: <String>[pack.surahNumber.toLocalisedString()],
        );
    final String reciterName = saved.reciter?.nameAr ?? pack.reciterId;

    final ThemeData theme = Theme.of(context);
    final String details =
        '$reciterName · '
        '${LocaleKeys.downloadsSizeMb.tr(args: <String>[megabytes(pack.bytes)])}'
        ' · '
        '${LocaleKeys.downloadsBitrate.tr(args: <String>[pack.bitrate.toLocalisedString()])}';

    return ListTile(
      contentPadding: EdgeInsetsDirectional.zero,
      leading: Icon(
        pack.isStale ? Icons.history : Icons.offline_pin_outlined,
        color: pack.isStale ? theme.colorScheme.tertiary : null,
      ),
      title: Text(surahName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(details),
          // Stale audio still plays — a superseded take beats silence — so
          // this is a note, not a warning, and the re-download is offered
          // beside the reciter rather than forced here.
          if (pack.isStale)
            Text(
              LocaleKeys.downloadsStale.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.tertiary,
              ),
            ),
        ],
      ),
      isThreeLine: pack.isStale,
      trailing: IconButton(
        onPressed: () => cubit.delete(saved),
        tooltip: LocaleKeys.downloadsDelete.tr(),
        icon: const Icon(Icons.delete_outline),
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.bytes, this.error});

  final int bytes;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: EdgeInsetsDirectional.only(top: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            LocaleKeys.downloadsSavedTotal.tr(args: <String>[megabytes(bytes)]),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (error != null)
            Padding(
              padding: EdgeInsetsDirectional.only(top: 8.h),
              child: Text(
                error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: EdgeInsetsDirectional.all(32.r),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.cloud_outlined,
              size: 48.r,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            SizedBox(height: 16.h),
            Text(
              LocaleKeys.downloadsSavedEmpty.tr(),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (message != null)
              Padding(
                padding: EdgeInsetsDirectional.only(top: 12.h),
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One decimal, and never a bare 0 for a pack that does exist.
String megabytes(int bytes) =>
    (bytes / (1024 * 1024)).clamp(0.1, double.infinity).toLocalisedFixed(1);
