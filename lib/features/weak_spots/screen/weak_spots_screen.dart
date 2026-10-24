import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../core/desktop.dart';
import '../../../core/di/injection.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/state/load_status.dart';
import '../../../core/widgets/panel.dart';
import '../../mushaf/mushaf_args.dart';
import '../../session/session_request.dart';
import '../../surah_list/widgets/error_view.dart';
import '../cubit/weak_spots_cubit.dart';

/// Every ayah the reader has said they stumble at: the one that trips them
/// most at the top, each a drill over that ayah alone, a way back to its
/// page, or the mark taken off.
class WeakSpotsScreen extends StatelessWidget {
  const WeakSpotsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider<WeakSpotsCubit>(
    create: (_) => sl<WeakSpotsCubit>()..load(),
    child: const _WeakSpotsView(),
  );
}

class _WeakSpotsView extends StatelessWidget {
  const _WeakSpotsView();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return BlocBuilder<WeakSpotsCubit, WeakSpotsState>(
      builder: (BuildContext context, WeakSpotsState state) => Scaffold(
        // The count and the order in the bar, under the title: what the
        // list is, said once.
        appBar: AppBar(
          title: state.spots.isEmpty
              ? Text(LocaleKeys.weakSpotsTitle.tr())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      LocaleKeys.weakSpotsTitle.tr(),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      LocaleKeys.weakSpotsSorted.tr(
                        args: <String>[state.spots.length.toLocalisedString()],
                      ),
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                ),
        ),
        body: DesktopWidth(
          child: Builder(
            builder: (BuildContext context) {
              if (state.status.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state.status.isFailure) {
                return ErrorView(
                  message: state.errorMessage ?? '',
                  onRetry: () => context.read<WeakSpotsCubit>().load(),
                );
              }
              if (state.spots.isEmpty) {
                return Center(
                  child: Padding(
                    padding: EdgeInsetsDirectional.all(32.r),
                    child: Text(
                      LocaleKeys.weakSpotsEmpty.tr(),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              // Most-stumbled first: which ayah trips the reader most is what
              // the screen is for. The cubit keeps the stored order, and a
              // stable sort leaves equal counts in it.
              final List<WeakSpot> spots = <WeakSpot>[...state.spots]
                ..sort(
                  (WeakSpot a, WeakSpot b) =>
                      b.record.stumbles.compareTo(a.record.stumbles),
                );

              return ListView(
                padding: EdgeInsetsDirectional.fromSTEB(16.w, 12.h, 16.w, 32.h),
                children: <Widget>[
                  AppCard(
                    padding: EdgeInsetsDirectional.zero,
                    child: Column(
                      children: <Widget>[
                        for (final WeakSpot spot in spots) ...<Widget>[
                          if (spot != spots.first) const Divider(height: 1),
                          _SpotTile(spot: spot),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(height: 16.h),
                  AppNote(LocaleKeys.weakSpotsNote.tr(), icon: Icons.repeat),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SpotTile extends StatelessWidget {
  const _SpotTile({required this.spot});

  final WeakSpot spot;

  Future<void> _open(BuildContext context, {required bool drill}) async {
    final WeakSpotsCubit cubit = context.read<WeakSpotsCubit>();
    await context.pushNamed<void>(
      AppRoutes.mushafName,
      extra: MushafArgs(
        initialAyah: spot.ref,
        session: drill
            ? SessionRequest(from: spot.ref, to: spot.ref, autostart: true)
            : null,
      ),
    );
    // The mark may have been taken off from the page.
    await cubit.load();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool arabic = context.locale.languageCode == 'ar';
    return ListTile(
      contentPadding: EdgeInsetsDirectional.fromSTEB(14.w, 4.h, 6.w, 4.h),
      minTileHeight: 60.r,
      leading: TileIcon(Icons.flag_outlined, color: theme.colorScheme.error),
      title: Text(
        LocaleKeys.mushafAyahReference.tr(
          args: <String>[
            arabic ? spot.surah.nameAr : spot.surah.nameEn,
            spot.ref.ayah.toLocalisedString(),
          ],
        ),
        style: theme.textTheme.titleSmall,
      ),
      // How often, and where: the page it is on, as the row is opened.
      subtitle: Text(
        joinDetails(<String>[
          LocaleKeys.weakSpotsCount.tr(
            args: <String>[spot.record.stumbles.toLocalisedString()],
          ),
          if (spot.page case final int page)
            LocaleKeys.mushafPage.tr(args: <String>[page.toLocalisedString()]),
        ]),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: () => _open(context, drill: false),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PlayButton(
            tooltip: LocaleKeys.weakSpotsDrill.tr(),
            onPressed: () => _open(context, drill: true),
            icon: Icons.repeat_one,
          ),
          // Quiet: taking the mark off is the rare thing here.
          IconButton(
            visualDensity: VisualDensity.compact,
            constraints: BoxConstraints.tightFor(width: 32.r, height: 40.r),
            padding: EdgeInsetsDirectional.zero,
            iconSize: 18.r,
            color: theme.colorScheme.onSurfaceVariant,
            tooltip: LocaleKeys.mushafClearStumble.tr(),
            onPressed: () => context.read<WeakSpotsCubit>().clear(spot),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}
