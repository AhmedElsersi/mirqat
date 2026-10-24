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
import '../../surah_list/widgets/surah_row.dart' show NumberDiamond;
import '../cubit/downloads_cubit.dart';
import '../cubit/downloads_state.dart';

/// What is saved for offline listening, and what it costs.
///
/// The total leads the screen rather than closing it, and a reciter's two
/// bulk actions — re-download what is stale, free the lot — sit on that
/// reciter's own row instead of as text buttons under their surahs.
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider<DownloadsCubit>(
    create: (_) => sl<DownloadsCubit>()..load(),
    child: Scaffold(
      appBar: AppBar(title: Text(LocaleKeys.downloadsSavedTitle.tr())),
      body: DesktopWidth(
        child: BlocBuilder<DownloadsCubit, DownloadsState>(
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
              padding: EdgeInsetsDirectional.fromSTEB(16.w, 12.h, 16.w, 32.h),
              children: <Widget>[
                if (state.busy)
                  Padding(
                    padding: EdgeInsetsDirectional.only(bottom: 12.h),
                    child: const LinearProgressIndicator(),
                  ),
                _Total(
                  bytes: state.totalBytes,
                  surahs: state.saved.length,
                  error: state.errorMessage,
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
              ],
            );
          },
        ),
      ),
    ),
  );
}

/// What it all costs, at the top: the first thing anyone opens this for.
class _Total extends StatelessWidget {
  const _Total({required this.bytes, required this.surahs, this.error});

  final int bytes;
  final int surahs;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AppCard(
      padding: EdgeInsetsDirectional.all(16.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const TileIcon(Icons.sd_storage_outlined),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      LocaleKeys.downloadsSizeMb.tr(
                        args: <String>[megabytes(bytes)],
                      ),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      LocaleKeys.downloadsSavedCount.tr(
                        args: <String>[surahs.toLocalisedString()],
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (error != null) ...<Widget>[
            SizedBox(height: 10.h),
            Text(
              error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One reciter's saved surahs, with the two actions that apply to all of
/// them on the reciter's own row.
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
    final SavedRecitation first = items.first;
    final String name = first.reciter?.nameAr ?? reciterId;
    final bool hasStale = items.any((SavedRecitation s) => s.pack.isStale);
    final int bytes = items.fold<int>(
      0,
      (int sum, SavedRecitation s) => sum + s.pack.bytes,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FieldLabel(name),
        AppCard(
          padding: EdgeInsetsDirectional.zero,
          child: Column(
            children: <Widget>[
              ListTile(
                leading: first.reciter == null
                    ? const TileIcon(Icons.person_outline)
                    : ReciterAvatar(reciter: first.reciter!, diameter: 40),
                title: Text(
                  LocaleKeys.downloadsSavedCount.tr(
                    args: <String>[items.length.toLocalisedString()],
                  ),
                  style: theme.textTheme.titleSmall,
                ),
                subtitle: Text(
                  joinDetails(<String>[
                    LocaleKeys.downloadsBitrate.tr(
                      args: <String>[first.pack.bitrate.toLocalisedString()],
                    ),
                    LocaleKeys.downloadsSizeMb.tr(
                      args: <String>[megabytes(bytes)],
                    ),
                  ]),
                ),
                trailing: PopupMenuButton<void>(
                  enabled: !busy,
                  tooltip: LocaleKeys.commonMore.tr(),
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<void>>[
                    if (hasStale)
                      PopupMenuItem<void>(
                        onTap: () => cubit.redownloadStale(reciterId),
                        child: _MenuRow(
                          icon: Icons.refresh,
                          label: LocaleKeys.downloadsRedownloadReciter.tr(),
                        ),
                      ),
                    PopupMenuItem<void>(
                      onTap: () => cubit.deleteReciter(reciterId),
                      child: _MenuRow(
                        icon: Icons.delete_sweep_outlined,
                        label: LocaleKeys.downloadsDeleteReciter.tr(),
                      ),
                    ),
                  ],
                ),
              ),
              for (final SavedRecitation saved in items) ...<Widget>[
                const Divider(height: 1),
                _SavedRow(saved: saved, cubit: cubit, busy: busy),
              ],
            ],
          ),
        ),
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FieldLabel(LocaleKeys.downloadsFailedRow.tr()),
        AppCard(
          padding: EdgeInsetsDirectional.zero,
          child: Column(
            children: <Widget>[
              for (final SavedRecitation saved in items) ...<Widget>[
                if (saved != items.first) const Divider(height: 1),
                ListTile(
                  leading: TileIcon(
                    Icons.cloud_off_outlined,
                    color: theme.colorScheme.error,
                  ),
                  title: Text(
                    saved.surah?.nameAr ??
                        saved.pack.surahNumber.toLocalisedString(),
                    style: theme.textTheme.titleSmall,
                  ),
                  subtitle: Text(
                    LocaleKeys.downloadsFailedStreams.tr(
                      args: <String>[
                        saved.reciter?.nameAr ?? saved.pack.reciterId,
                      ],
                    ),
                  ),
                  trailing: IconButton(
                    onPressed: busy ? null : () => cubit.delete(saved),
                    tooltip: LocaleKeys.downloadsDelete.tr(),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: 12.h),
        OutlinedButton.icon(
          onPressed: busy ? null : cubit.retryFailed,
          icon: const Icon(Icons.refresh),
          label: Text(
            LocaleKeys.downloadsRetryFailed.tr(
              args: <String>[items.length.toLocalisedString()],
            ),
          ),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Icon(icon),
      SizedBox(width: 10.w),
      Flexible(child: Text(label)),
    ],
  );
}

/// One saved surah: which it is, what it cost, and the way to free it.
class _SavedRow extends StatelessWidget {
  const _SavedRow({
    required this.saved,
    required this.cubit,
    required this.busy,
  });

  final SavedRecitation saved;
  final DownloadsCubit cubit;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final InstalledPack pack = saved.pack;
    // A surah the catalog no longer knows still has to name itself, or the
    // row would be an anonymous delete button.
    final String surahName =
        saved.surah?.nameAr ??
        LocaleKeys.commonAyahNumber.tr(
          args: <String>[pack.surahNumber.toLocalisedString()],
        );

    final ThemeData theme = Theme.of(context);
    return ListTile(
      leading: NumberDiamond(number: pack.surahNumber),
      title: Text(surahName, style: theme.textTheme.titleSmall),
      // Stale audio still plays — a superseded take beats silence — so it
      // is a tag, not a warning, and the re-download beside it asks rather
      // than insists.
      subtitle: pack.isStale
          ? Wrap(
              spacing: 6.w,
              runSpacing: 4.h,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                AppTag(label: LocaleKeys.downloadsStale.tr(), gold: true),
                Text(LocaleKeys.downloadsStaleNewer.tr()),
              ],
            )
          : Text(
              LocaleKeys.downloadsSizeMb.tr(
                args: <String>[megabytes(pack.bytes)],
              ),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (pack.isStale)
            IconButton(
              onPressed: busy ? null : () => cubit.redownload(saved),
              tooltip: LocaleKeys.downloadsRedownload.tr(),
              icon: const Icon(Icons.refresh),
            ),
          IconButton(
            onPressed: busy ? null : () => cubit.delete(saved),
            tooltip: LocaleKeys.downloadsDelete.tr(),
            icon: const Icon(Icons.delete_outline),
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
