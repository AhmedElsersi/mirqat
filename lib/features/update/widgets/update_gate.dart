import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/di/injection.dart';
import '../../../core/localization/locale_keys.dart';
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
///    "later", and not again for a day.
///
/// Drawn here, in the app's own tree, rather than as a route: it has to sit
/// over whichever screen is up, the splash aside, and must not be something a
/// back gesture can pop.
class UpdateGate extends StatelessWidget {
  const UpdateGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UpdateCubit, UpdateState>(
      builder: (BuildContext context, UpdateState state) => Stack(
        children: <Widget>[
          // Still there underneath, and still running: an optional prompt
          // must not cost a session its place.
          child,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            LocaleKeys.updateWhatsNew.tr(),
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          SizedBox(height: 4.h),
          Text(notes, style: theme.textTheme.bodyMedium?.copyWith(height: 1.7)),
        ],
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
      padding: EdgeInsetsDirectional.all(24.r),
      child: Material(
        color: theme.colorScheme.surface,
        elevation: 8,
        borderRadius: BorderRadius.circular(24.r),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 420.w),
          child: SingleChildScrollView(
            padding: EdgeInsetsDirectional.all(24.r),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.system_update_outlined,
                  size: 36.r,
                  color: theme.colorScheme.primary,
                ),
                SizedBox(height: 12.h),
                Text(
                  LocaleKeys.updateOptionalTitle.tr(),
                  style: theme.textTheme.titleLarge,
                ),
                SizedBox(height: 8.h),
                Text(
                  LocaleKeys.updateOptionalBody.tr(),
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.7),
                ),
                _Notes(state: state),
                SizedBox(height: 20.h),
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
                      child: FilledButton(
                        onPressed: () => _openStore(context, state),
                        child: Text(LocaleKeys.updateNow.tr()),
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

    // Swallows the back gesture: there is nothing behind this to go back to.
    return PopScope(
      canPop: false,
      child: Material(
        color: theme.scaffoldBackgroundColor,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsetsDirectional.all(32.r),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.system_update_outlined,
                    size: 64.r,
                    color: theme.colorScheme.primary,
                  ),
                  SizedBox(height: 24.h),
                  Text(
                    LocaleKeys.updateRequiredTitle.tr(),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  SizedBox(height: 12.h),
                  Text(
                    LocaleKeys.updateRequiredBody.tr(),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.8),
                  ),
                  _Notes(state: state),
                  SizedBox(height: 28.h),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => _openStore(context, state),
                      child: Text(LocaleKeys.updateNow.tr()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
