import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/bootstrap.dart';
import '../../../core/di/injection.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/ladder_mark.dart';
import '../../../core/widgets/panel.dart';
import '../../../data/models/app_info.dart';
import '../../../services/link_opener.dart';
import '../../../services/update_policy.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../cubit/update_cubit.dart';

/// Sits over the whole app and says what there is to say about updating.
///
/// Two levels, set per store in `app.json`:
///
///  * **required** — this version is older than the oldest still allowed. A
///    page over everything, with one button. There is no way past it, which
///    is why the rule that raises it is so hard to raise by accident (see
///    `decideUpdate`).
///  * **optional** — a newer version is out. A card over a dimmed app, with
///    "later", and not again for a day (or as long as the rules say).
///  * **maintenance** — the closed sign is up. A page over everything, with
///    the words the sign carries and a way to ask again. Ahead of both.
///
/// Drawn here, in the app's own tree, rather than as a route: it has to sit
/// over whichever screen is up, the splash aside, and must not be something a
/// back gesture can pop.
class UpdateGate extends StatefulWidget {
  const UpdateGate({required this.child, super.key});

  final Widget child;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  /// Whether startup has finished, and with it the registration of everything
  /// the update cubit is made from.
  ///
  /// This widget is built on the app's very first frame, under the splash,
  /// and its cubit is created the moment something reads it — so reading it
  /// before startup is done asks the locator for services that are not there
  /// yet, and the app opens on an error instead of a splash. Until then the
  /// gate is simply not there.
  bool _started = false;

  @override
  void initState() {
    super.initState();
    AppBootstrap.future.then((_) {
      if (mounted) setState(() => _started = true);
    }, onError: (Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_started) return widget.child;
    return BlocBuilder<UpdateCubit, UpdateState>(
      builder: (BuildContext context, UpdateState state) => Stack(
        children: <Widget>[
          // Still there underneath, and still running: an optional prompt
          // must not cost a session its place.
          widget.child,
          if (state.kind == UpdateKind.optional) ...<Widget>[
            ModalBarrier(
              dismissible: false,
              color: Theme.of(
                context,
              ).colorScheme.scrim.withValues(alpha: 0.54),
            ),
            Center(child: _OptionalCard(state: state)),
          ],
          if (state.kind == UpdateKind.required)
            Positioned.fill(child: _RequiredPage(state: state)),
          if (state.maintenance case final Maintenance sign)
            Positioned.fill(
              child: _MaintenancePage(sign: sign, state: state),
            ),
        ],
      ),
    );
  }
}

Future<void> _openStore(BuildContext context, UpdateState state) async {
  final Uri? store = Uri.tryParse(state.storeUrl.trim());
  if (store == null) return;
  await sl<LinkOpener>().open(store);
}

class _Notes extends StatelessWidget {
  const _Notes({required this.state});

  final UpdateState state;

  @override
  Widget build(BuildContext context) {
    final String notes = state.notes.of(context.locale.languageCode);
    if (notes.isEmpty) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsetsDirectional.only(top: 16.h),
      child: AppCard(
        filled: true,
        padding: EdgeInsetsDirectional.all(16.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              LocaleKeys.updateWhatsNew.tr(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              notes,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.7),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionalCard extends StatelessWidget {
  const _OptionalCard({required this.state});

  final UpdateState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: EdgeInsetsDirectional.symmetric(horizontal: 16.w),
      child: Material(
        color: theme.colorScheme.surface,
        elevation: 8,
        borderRadius: BorderRadius.circular(26.r),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 420.w),
          child: SingleChildScrollView(
            padding: EdgeInsetsDirectional.symmetric(
              horizontal: 20.w,
              vertical: 24.h,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Align(child: LadderMark(current: 2)),
                SizedBox(height: 16.h),
                Text(
                  LocaleKeys.updateOptionalTitle.tr(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  LocaleKeys.updateOptionalBody.tr(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.7,
                  ),
                ),
                _Notes(state: state),
                SizedBox(height: 18.h),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          // Written down first: "later" is a day's quiet, and
                          // it should hold even if the app is closed next.
                          context.read<SettingsCubit>().markUpdatePrompted(
                            DateTime.now(),
                          );
                          context.read<UpdateCubit>().dismiss();
                        },
                        child: Text(LocaleKeys.updateLater.tr()),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _openStore(context, state),
                        icon: const Icon(Icons.download_outlined),
                        label: Text(LocaleKeys.updateNow.tr()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RequiredPage extends StatelessWidget {
  const _RequiredPage({required this.state});

  final UpdateState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    // Not a route, so there is nothing here for a back gesture to pop: back
    // goes to the navigator underneath — and, from the home page, out of the
    // app — while this stays where it is.
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsetsDirectional.all(32.r),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const _Seal(Icons.system_update_outlined),
                _Title(LocaleKeys.updateRequiredTitle.tr()),
                _Body(LocaleKeys.updateRequiredBody.tr()),
                // Which version is wanted, where the rule names one — in the
                // tag the closed sign gives to when the app is back.
                if (state.target.isNotEmpty) ...<Widget>[
                  SizedBox(height: 16.h),
                  AppTag(
                    label: LocaleKeys.updateTargetVersion.tr(
                      args: <String>[state.target],
                    ),
                  ),
                ],
                _Notes(state: state),
                SizedBox(height: 26.h),
                FilledButton.icon(
                  onPressed: () => _openStore(context, state),
                  icon: const Icon(Icons.download_outlined),
                  label: Text(LocaleKeys.updateNow.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The closed sign: the words it carries, when to expect the app back if a
/// time was given, and a way to ask again. Like the required page, not a
/// route, so nothing pops it.
class _MaintenancePage extends StatelessWidget {
  const _MaintenancePage({required this.sign, required this.state});

  final Maintenance sign;
  final UpdateState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String lang = context.locale.languageCode;
    final String title = sign.title.of(lang).trim();
    final String message = sign.message.of(lang).trim();
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsetsDirectional.all(32.r),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const _Seal(Icons.build_outlined),
                _Title(
                  title.isEmpty
                      ? LocaleKeys.updateMaintenanceTitle.tr()
                      : title,
                ),
                _Body(
                  message.isEmpty
                      ? LocaleKeys.updateMaintenanceBody.tr()
                      : message,
                ),
                if (sign.until case final DateTime until) ...<Widget>[
                  SizedBox(height: 16.h),
                  // When to expect the app back: a sign nobody remembered
                  // cannot keep people out for good, and this says so.
                  AppTag(
                    label: LocaleKeys.updateMaintenanceUntil.tr(
                      args: <String>[_clock(context, until.toLocal())],
                    ),
                  ),
                ],
                SizedBox(height: 26.h),
                FilledButton.icon(
                  onPressed: state.retrying
                      ? null
                      : () => context.read<UpdateCubit>().retry(),
                  icon: const Icon(Icons.refresh),
                  label: Text(LocaleKeys.updateRetry.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The time, in the phone's own zone and the reader's digits — «١٠:٣٠ م»
  /// — with the date before it only where it is not today.
  static String _clock(BuildContext context, DateTime t) {
    final String locale = context.locale.toString();
    final DateTime now = DateTime.now();
    final bool today =
        t.year == now.year && t.month == now.month && t.day == now.day;
    final DateFormat format = today
        ? DateFormat.jm(locale)
        : DateFormat.MMMd(locale).add_jm();
    return format.format(t).withLocalisedDigits();
  }
}

/// The heading of a page that is the only thing on screen.
class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    style: Theme.of(
      context,
    ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
  );
}

/// What such a page says under its heading: quiet, and kept to a short
/// measure so it reads as a line or two rather than a paragraph.
class _Body extends StatelessWidget {
  const _Body(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsetsDirectional.only(top: 10.h),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 280.w),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.7,
          ),
        ),
      ),
    );
  }
}

/// The mark on a page that is the only thing on screen: the icon set in a
/// gold wash, which is the one place gold is a surface — a seal, not a fill.
class _Seal extends StatelessWidget {
  const _Seal(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 78.r,
    height: 78.r,
    margin: EdgeInsetsDirectional.only(bottom: 18.h),
    decoration: BoxDecoration(
      color: AppColors.gold.withValues(alpha: 0.2),
      shape: BoxShape.circle,
    ),
    child: Icon(
      icon,
      size: 34.r,
      color: Theme.of(context).colorScheme.onSurface,
    ),
  );
}
