import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/injection.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/router/app_routes.dart';
import '../../home/cubit/home_index_cubit.dart';
import '../../home/cubit/home_index_state.dart';
import '../../mushaf/mushaf_args.dart';

/// Where the reader has been, newest first: the last twenty visits, each one
/// a way back to its page. Kept on the device and nowhere else.
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
          body: !state.loaded
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
              : ListView.separated(
                  padding: EdgeInsetsDirectional.only(bottom: 24.h),
                  itemCount: state.history.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) => PlaceTile(
                    place: state.history[index],
                    onTap: () async {
                      await openPlace(context, state.history[index]);
                      await cubit.refreshHistory();
                    },
                  ),
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

/// Opens the mushaf on the page a place is on.
Future<void> openPlace(BuildContext context, PlaceItem place) =>
    context.pushNamed<void>(
      AppRoutes.mushafName,
      extra: MushafArgs(initialPage: place.position.page),
    );

/// One visited place: the surah, the ayah and page, and when.
class PlaceTile extends StatelessWidget {
  const PlaceTile({required this.place, required this.onTap, super.key});

  final PlaceItem place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool arabic = context.locale.languageCode == 'ar';
    return ListTile(
      onTap: onTap,
      leading: Icon(Icons.bookmark_outline, color: theme.colorScheme.primary),
      title: Text(
        LocaleKeys.homePlace.tr(
          args: <String>[
            arabic ? place.surah.nameAr : place.surah.nameEn,
            place.position.ayahNumber.toLocalisedString(),
            place.position.page.toLocalisedString(),
          ],
        ),
      ),
      subtitle: Text(whenLabel(context, place.position.at)),
      trailing: const Icon(Icons.chevron_right),
    );
  }

  /// "Today 3:15 PM", "Yesterday 9:02 AM", or the date — in the app's own
  /// language and numerals.
  static String whenLabel(BuildContext context, DateTime at) {
    final String locale = context.locale.toString();
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime day = DateTime(at.year, at.month, at.day);
    final String time = DateFormat.jm(locale).format(at).withLocalisedDigits();
    if (day == today) return '${LocaleKeys.historyToday.tr()} · $time';
    if (day == today.subtract(const Duration(days: 1))) {
      return '${LocaleKeys.historyYesterday.tr()} · $time';
    }
    final String date = DateFormat.yMMMd(locale).format(at);
    return '${date.withLocalisedDigits()} · $time';
  }
}
