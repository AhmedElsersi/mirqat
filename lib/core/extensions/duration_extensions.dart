import 'package:easy_localization/easy_localization.dart';

import '../localization/locale_keys.dart';
import 'number_extensions.dart';

extension DurationFormatting on Duration {
  /// "4 د 12 ث" / "4 min 12 s", dropping the empty half.
  String get localized {
    final int minutes = inMinutes;
    final int seconds = inSeconds - minutes * 60;

    if (minutes == 0) {
      return LocaleKeys.durationSeconds.tr(
        args: <String>[seconds.toLocalisedString()],
      );
    }
    if (seconds == 0) {
      return LocaleKeys.durationMinutes.tr(
        args: <String>[minutes.toLocalisedString()],
      );
    }
    return LocaleKeys.durationMinutesSeconds.tr(
      args: <String>[minutes.toLocalisedString(), seconds.toLocalisedString()],
    );
  }
}
