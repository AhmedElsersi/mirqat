import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/locale_keys.dart';
import '../../../core/router/app_routes.dart';
import '../../../domain/entities/daily_wird.dart';
import '../../mushaf/mushaf_args.dart';
import '../../session/session_request.dart';

/// The words a part of the wird goes by — the same as its chip in the
/// session sheet, so the two read as one thing.
String wirdPartLabel(WirdPart part) => switch (part) {
  WirdPart.fresh => LocaleKeys.presetsNew.tr(),
  WirdPart.recent => LocaleKeys.presetsRecent.tr(),
  WirdPart.old => LocaleKeys.presetsOld.tr(),
};

/// How a part is worked: new is the reader's own defaults; the reviews are
/// the sheet's lighter ways of working.
SessionPreset wirdPartPreset(WirdPart part) => switch (part) {
  WirdPart.fresh => const SessionPreset(),
  WirdPart.recent => SessionPreset.recent,
  WirdPart.old => SessionPreset.old,
};

/// Opens the reading view on [range], set up the way [part] is worked, with
/// its chip shown chosen in the sheet.
void openWirdPart(BuildContext context, WirdPart part, WirdRange range) =>
    context.pushNamed<void>(
      AppRoutes.mushafName,
      extra: MushafArgs(
        initialAyah: range.from,
        session: SessionRequest(
          from: range.from,
          to: range.to,
          preset: wirdPartPreset(part),
          presetKey: part.key,
          autostart: true,
        ),
      ),
    );
