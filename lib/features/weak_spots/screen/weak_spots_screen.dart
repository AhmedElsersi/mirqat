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
import '../../mushaf/mushaf_args.dart';
import '../../session/session_request.dart';
import '../../surah_list/widgets/error_view.dart';
import '../cubit/weak_spots_cubit.dart';

/// Every ayah the reader has said they stumble at, the most recent first:
/// each one a way back to its page, a drill over it alone, or the mark
/// taken off.
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
    return Scaffold(
      appBar: AppBar(title: Text(LocaleKeys.weakSpotsTitle.tr())),
      body: DesktopWidth(
        child: BlocBuilder<WeakSpotsCubit, WeakSpotsState>(
          builder: (BuildContext context, WeakSpotsState state) {
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
            return ListView.separated(
              padding: EdgeInsetsDirectional.only(bottom: 24.h),
              itemCount: state.spots.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (BuildContext context, int i) =>
                  _SpotTile(spot: state.spots[i]),
            );
          },
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
      leading: Icon(Icons.flag_outlined, color: theme.colorScheme.error),
      title: Text(
        LocaleKeys.mushafAyahReference.tr(
          args: <String>[
            arabic ? spot.surah.nameAr : spot.surah.nameEn,
            spot.ref.ayah.toLocalisedString(),
          ],
        ),
      ),
      subtitle: Text(
        LocaleKeys.weakSpotsCount.tr(
          args: <String>[spot.record.stumbles.toLocalisedString()],
        ),
      ),
      onTap: () => _open(context, drill: false),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            tooltip: LocaleKeys.weakSpotsDrill.tr(),
            onPressed: () => _open(context, drill: true),
            icon: const Icon(Icons.repeat_one),
          ),
          IconButton(
            tooltip: LocaleKeys.mushafClearStumble.tr(),
            onPressed: () => context.read<WeakSpotsCubit>().clear(spot),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}
