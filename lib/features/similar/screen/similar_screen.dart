import 'package:easy_localization/easy_localization.dart' hide TextDirection;
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
import '../../../core/widgets/ayah_text.dart';
import '../../../data/models/word.dart';
import '../../../domain/entities/ayah_ref.dart';
import '../../mushaf/mushaf_args.dart';
import '../../session/session_request.dart';
import '../../surah_list/widgets/error_view.dart';
import '../cubit/similar_cubit.dart';

/// An ayah, and below it the ayahs it is easily confused with, each with the
/// words they share marked — so the reader sees, before they slip, exactly
/// where two ayahs part.
class SimilarScreen extends StatelessWidget {
  const SimilarScreen({required this.ayah, super.key});

  final AyahRef ayah;

  @override
  Widget build(BuildContext context) => BlocProvider<SimilarCubit>(
    create: (_) => sl<SimilarCubit>()..load(ayah),
    child: Scaffold(
      appBar: AppBar(title: Text(LocaleKeys.similarTitle.tr())),
      body: DesktopWidth(
        child: BlocBuilder<SimilarCubit, SimilarState>(
          builder: (BuildContext context, SimilarState state) {
            if (state.status.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            final ComparedAyah? target = state.target;
            if (state.status.isFailure || target == null) {
              return ErrorView(
                message: state.errorMessage ?? LocaleKeys.commonError.tr(),
                onRetry: () => context.read<SimilarCubit>().load(ayah),
              );
            }
            return ListView(
              padding: EdgeInsetsDirectional.all(12.r),
              children: <Widget>[
                _AyahCard(item: target, emphasised: true),
                Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(4.w, 16.h, 4.w, 8.h),
                  child: Text(
                    state.similar.isEmpty
                        ? LocaleKeys.similarNone.tr()
                        : LocaleKeys.similarCount.tr(
                            args: <String>[
                              state.similar.length.toLocalisedString(),
                            ],
                          ),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                for (final ComparedAyah item in state.similar)
                  _AyahCard(item: item),
                SizedBox(height: 8.h),
                Text(
                  LocaleKeys.similarSource.tr(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _AyahCard extends StatelessWidget {
  const _AyahCard({required this.item, this.emphasised = false});

  final ComparedAyah item;

  /// The ayah being compared from, set apart from the ones it resembles.
  final bool emphasised;

  void _open(BuildContext context, {required bool listen}) => context.pushNamed(
    AppRoutes.mushafName,
    extra: MushafArgs(
      initialAyah: item.ref,
      session: listen
          ? SessionRequest(
              from: item.ref,
              to: item.ref,
              preset: SessionPreset.listen,
              autostart: true,
            )
          : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool arabic = context.locale.languageCode == 'ar';
    return Card(
      color: emphasised
          ? theme.colorScheme.primary.withValues(alpha: 0.06)
          : null,
      margin: EdgeInsetsDirectional.only(bottom: 10.h),
      child: InkWell(
        onTap: () => _open(context, listen: false),
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(12.w, 8.h, 4.w, 12.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      LocaleKeys.mushafAyahReference.tr(
                        args: <String>[
                          arabic ? item.surah.nameAr : item.surah.nameEn,
                          item.ref.ayah.toLocalisedString(),
                        ],
                      ),
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: LocaleKeys.similarListen.tr(),
                    onPressed: () => _open(context, listen: true),
                    icon: const Icon(Icons.headphones_outlined),
                  ),
                ],
              ),
              // The ayah's own words, as the mushaf prints them, wrapping
              // where the card ends; the words it shares tinted.
              Directionality(
                textDirection: TextDirection.rtl,
                child: Wrap(
                  spacing: 6.w,
                  runSpacing: 2.h,
                  children: <Widget>[
                    for (final Word w in item.words)
                      AyahText.word(
                        text: w.text,
                        fontSize: 22.sp,
                        isMarker: w.isMarker,
                        tint: item.isShared(w)
                            ? WordTint.highlighted
                            : WordTint.none,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
