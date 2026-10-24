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
import '../../../domain/entities/ayah_ref.dart';
import '../../surah_list/widgets/error_view.dart';
import '../cubit/similar_cubit.dart';
import '../widgets/compared_ayah_card.dart';

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
              padding: EdgeInsetsDirectional.fromSTEB(16.w, 12.h, 16.w, 24.h),
              children: <Widget>[
                ComparedAyahCard(item: target, emphasised: true),
                if (state.similar.isEmpty)
                  Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(
                      4.w,
                      16.h,
                      4.w,
                      8.h,
                    ),
                    child: Text(
                      LocaleKeys.similarNone.tr(),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  FieldLabel(
                    LocaleKeys.similarCount.tr(
                      args: <String>[state.similar.length.toLocalisedString()],
                    ),
                  ),
                for (final ComparedAyah item in state.similar)
                  ComparedAyahCard(item: item),
                SizedBox(height: 8.h),
                AppNote(
                  LocaleKeys.similarSource.tr(),
                  icon: Icons.bookmarks_outlined,
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
