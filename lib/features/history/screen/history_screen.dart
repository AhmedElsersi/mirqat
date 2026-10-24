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
import '../../../core/widgets/panel.dart';
import '../../home/cubit/home_index_cubit.dart';
import '../../home/cubit/home_index_state.dart';
import '../../mushaf/mushaf_args.dart';
import '../../surah_list/widgets/surah_row.dart' show NumberDiamond;

/// Where the reader has been, newest first: the last twenty visits, each one
/// a way back to its page. Kept on the device and nowhere else.
///
/// The visits are gathered under the day they belong to, so the date is said
/// once over a group instead of on every row, and what a row then carries is
/// the place and the hour.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider<HomeIndexCubit>(
    create: (_) => sl<HomeIndexCubit>()..load(),
    child: const _HistoryView(),
  );
}

class _HistoryView extends StatelessWidget {
  const _HistoryView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeIndexCubit, HomeIndexState>(
      builder: (BuildContext context, HomeIndexState state) {
        final HomeIndexCubit cubit = context.read<HomeIndexCubit>();
        return Scaffold(
          appBar: AppBar(
            title: Text(LocaleKeys.historyTitle.tr()),
            actions: <Widget>[
              if (state.history.isNotEmpty)
                IconButton(
                  tooltip: LocaleKeys.historyClear.tr(),
                  onPressed: () => _confirmClear(context, cubit),
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          body: DesktopWidth(
            child: !state.loaded
                ? const Center(child: CircularProgressIndicator())
                : state.history.isEmpty
                ? Center(
                    child: Padding(
                      padding: EdgeInsetsDirectional.all(32.r),
                      child: Text(
                        LocaleKeys.historyEmpty.tr(),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : _Days(places: state.history, onOpened: cubit.refreshHistory),
          ),
        );
      },
    );
  }

  static Future<void> _confirmClear(
    BuildContext context,
    HomeIndexCubit cubit,
  ) async {
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        content: Text(LocaleKeys.historyClearConfirm.tr()),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(LocaleKeys.commonCancel.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(LocaleKeys.historyClear.tr()),
          ),
        ],
      ),
    );
    if (yes ?? false) await cubit.clearHistory();
  }
}

/// The places, in the order they were visited, under a heading per day.
class _Days extends StatelessWidget {
  const _Days({required this.places, required this.onOpened});

  final List<PlaceItem> places;
  final Future<void> Function() onOpened;

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = <Widget>[];
    String? day;
    List<PlaceItem> group = <PlaceItem>[];

    void flush() {
      if (group.isEmpty) return;
      final List<PlaceItem> rows = group;
      children.add(
        AppCard(
          padding: EdgeInsetsDirectional.zero,
          child: Column(
            children: <Widget>[
              for (final PlaceItem place in rows) ...<Widget>[
                if (place != rows.first) const Divider(height: 1),
                PlaceTile(
                  place: place,
                  onTap: () async {
                    await openPlace(context, place);
                    await onOpened();
                  },
                ),
              ],
            ],
          ),
        ),
      );
      group = <PlaceItem>[];
    }

    for (final PlaceItem place in places) {
      final String label = PlaceTile.dayLabel(context, place.position.at);
      if (label != day) {
        flush();
        day = label;
        children.add(FieldLabel(label));
      }
      group.add(place);
    }
    flush();
    children.add(
      Padding(
        padding: EdgeInsetsDirectional.only(top: 18.h),
        child: AppNote(
          LocaleKeys.historyOnDevice.tr(),
          icon: Icons.smartphone_outlined,
        ),
      ),
    );

    return ListView(
      padding: EdgeInsetsDirectional.fromSTEB(16.w, 4.h, 16.w, 24.h),
      children: children,
    );
  }
}

/// Opens the mushaf on the page a place is on.
Future<void> openPlace(BuildContext context, PlaceItem place) =>
    context.pushNamed<void>(
      AppRoutes.mushafName,
      extra: MushafArgs(initialPage: place.position.page),
    );

/// One visited place: the page it is on, the ayah, and the hour.
class PlaceTile extends StatelessWidget {
  const PlaceTile({required this.place, required this.onTap, super.key});

  final PlaceItem place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool arabic = context.locale.languageCode == 'ar';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(14.w, 10.h, 10.w, 10.h),
        child: Row(
          children: <Widget>[
            // The page leads the row: it is what the mushaf opens on.
            NumberDiamond(number: place.position.page),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    LocaleKeys.historyPlace.tr(
                      args: <String>[
                        arabic ? place.surah.nameAr : place.surah.nameEn,
                        place.position.ayahNumber.toLocalisedString(),
                      ],
                    ),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  // The day is the group's heading; under the ayah, only
                  // the hour.
                  Text(
                    whenLabel(context, place.position.at),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  /// The hour a place was visited, in the app's own numerals.
  static String whenLabel(BuildContext context, DateTime at) =>
      DateFormat.jm(context.locale.toString()).format(at).withLocalisedDigits();

  /// The day a place belongs to: today, yesterday, or its date.
  static String dayLabel(BuildContext context, DateTime at) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime day = DateTime(at.year, at.month, at.day);
    if (day == today) return LocaleKeys.historyToday.tr();
    if (day == today.subtract(const Duration(days: 1))) {
      return LocaleKeys.historyYesterday.tr();
    }
    return DateFormat.yMMMd(
      context.locale.toString(),
    ).format(at).withLocalisedDigits();
  }
}
