import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/di/injection.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../data/models/audio_pack.dart';
import '../../../data/models/reciter.dart';
import '../../../data/models/surah.dart';
import '../cubit/audio_pack_cubit.dart';

/// Where this surah's recitation comes from, and the one action that changes
/// it: download it, or free it again.
///
/// Reading never depends on any of this and playback never fails because of
/// it — a surah with no pack streams — so the whole control is a quiet line of
/// text with a trailing button, never a prompt or a gate.
class AudioPackTile extends StatefulWidget {
  const AudioPackTile({required this.reciter, required this.surah, super.key});

  final Reciter reciter;
  final Surah surah;

  @override
  State<AudioPackTile> createState() => _AudioPackTileState();
}

class _AudioPackTileState extends State<AudioPackTile> {
  // Its own cubit, created here rather than by the screen: a download outlives
  // the drawer it was started from, and this control is the only thing that
  // cares about its progress.
  late final AudioPackCubit _cubit = sl<AudioPackCubit>();

  @override
  void initState() {
    super.initState();
    _watch();
  }

  @override
  void didUpdateWidget(AudioPackTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reciter.id != widget.reciter.id ||
        oldWidget.surah.number != widget.surah.number) {
      _watch();
    }
  }

  void _watch() => _cubit.watch(reciter: widget.reciter, surah: widget.surah);

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider<AudioPackCubit>.value(
    value: _cubit,
    child: BlocBuilder<AudioPackCubit, AudioPackState>(
      bloc: _cubit,
      builder: (BuildContext context, AudioPackState state) =>
          _Body(state: state, cubit: _cubit),
    ),
  );
}

class _Body extends StatelessWidget {
  const _Body({required this.state, required this.cubit});

  final AudioPackState state;
  final AudioPackCubit cubit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PackDownload download = state.download;

    // A surah that ships in the app has nothing to fetch and nothing to free,
    // and one no reciter offers remotely has nowhere to fetch from. Both are
    // states worth *saying* — "included in the app" is reassuring — but
    // neither gets a button.
    final bool actionable = !state.isBundled && state.canDownload;

    return Padding(
      padding: EdgeInsetsDirectional.only(bottom: 20.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            LocaleKeys.downloadsSection.tr(),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: 8.h),
          Row(
            children: <Widget>[
              Icon(_icon(state), size: 20.r, color: _colour(theme, state)),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  _label(state),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: download.status == PackStatus.failed
                        ? theme.colorScheme.error
                        : null,
                  ),
                ),
              ),
              if (actionable) _Action(state: state, cubit: cubit),
            ],
          ),
          if (download.isBusy) ...<Widget>[
            SizedBox(height: 8.h),
            LinearProgressIndicator(
              // Indeterminate until the platform reports a real fraction, and
              // indeterminate again while hashing and unzipping, which have
              // no percentage to report.
              value:
                  download.status == PackStatus.downloading &&
                      download.progress > 0
                  ? download.progress
                  : null,
              minHeight: 4.h,
            ),
          ],
        ],
      ),
    );
  }

  IconData _icon(AudioPackState state) {
    if (state.isBundled) return Icons.inventory_2_outlined;
    return switch (state.download.status) {
      PackStatus.failed => Icons.error_outline,
      PackStatus.installed => Icons.offline_pin_outlined,
      _ when state.isInstalled => Icons.offline_pin_outlined,
      PackStatus.queued ||
      PackStatus.downloading ||
      PackStatus.verifying ||
      PackStatus.installing => Icons.downloading_outlined,
      _ => Icons.cloud_outlined,
    };
  }

  Color? _colour(ThemeData theme, AudioPackState state) =>
      state.download.status == PackStatus.failed
      ? theme.colorScheme.error
      : theme.colorScheme.onSurfaceVariant;

  String _label(AudioPackState state) {
    if (state.isBundled) return LocaleKeys.downloadsBundled.tr();

    return switch (state.download.status) {
      PackStatus.queued => LocaleKeys.downloadsQueued.tr(),
      PackStatus.downloading => LocaleKeys.downloadsDownloading.tr(
        args: <String>[
          (state.download.progress * 100)
              .clamp(0, 100)
              .round()
              .toLocalisedString(),
        ],
      ),
      PackStatus.verifying => LocaleKeys.downloadsVerifying.tr(),
      PackStatus.installing => LocaleKeys.downloadsInstalling.tr(),
      PackStatus.failed => LocaleKeys.downloadsFailed.tr(),
      PackStatus.cancelled when !state.isInstalled =>
        LocaleKeys.downloadsCancelled.tr(),
      _ =>
        state.isInstalled
            ? LocaleKeys.downloadsOnDevice.tr(
                args: <String>[_megabytes(state.installed!.bytes)],
              )
            : LocaleKeys.downloadsStreaming.tr(),
    };
  }

  /// One decimal is as precise as a size like this deserves; a pack under
  /// 0.1 MB is still shown as 0.1 rather than 0.
  static String _megabytes(int bytes) =>
      (bytes / (1024 * 1024)).clamp(0.1, double.infinity).toLocalisedFixed(1);
}

/// Download, cancel, retry or free — whichever one the current state allows.
class _Action extends StatelessWidget {
  const _Action({required this.state, required this.cubit});

  final AudioPackState state;
  final AudioPackCubit cubit;

  @override
  Widget build(BuildContext context) {
    if (state.download.isBusy) {
      return IconButton(
        onPressed: cubit.cancel,
        tooltip: LocaleKeys.commonCancel.tr(),
        icon: const Icon(Icons.close),
      );
    }
    if (state.isInstalled) {
      return IconButton(
        onPressed: cubit.delete,
        tooltip: LocaleKeys.downloadsDelete.tr(),
        icon: const Icon(Icons.delete_outline),
      );
    }
    return IconButton(
      onPressed: cubit.download,
      tooltip: state.download.status == PackStatus.failed
          ? LocaleKeys.commonRetry.tr()
          : LocaleKeys.downloadsDownload.tr(),
      icon: Icon(
        state.download.status == PackStatus.failed
            ? Icons.refresh
            : Icons.download_outlined,
      ),
    );
  }
}
