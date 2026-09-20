import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/router/app_router.dart';
import 'package:mirqat/core/router/app_routes.dart';
import 'package:mirqat/core/state/load_status.dart';
import 'package:mirqat/data/models/app_settings.dart';
import 'package:mirqat/features/settings/cubit/settings_state.dart';

/// Where the splash gives way to.
void main() {
  test('someone who has not seen the introduction gets it', () {
    expect(
      AppRouter.landingAfterSplash(const SettingsState(settingsRead: true)),
      AppRoutes.onboardingPath,
    );
  });

  test('someone who has goes home', () {
    expect(
      AppRouter.landingAfterSplash(
        const SettingsState(
          settingsRead: true,
          settings: AppSettings(onboardingSeen: true),
        ),
      ),
      AppRoutes.surahListPath,
    );
  });

  test('settings that were never read are not a first launch', () {
    // An introduction shown by mistake to someone who has used the app for a
    // year is the worse of the two errors.
    expect(
      AppRouter.landingAfterSplash(const SettingsState()),
      AppRoutes.surahListPath,
    );
  });

  test('the reciters still loading does not put the introduction off', () {
    // They may be waiting on the network; what is stored on the device is
    // already known.
    expect(
      AppRouter.landingAfterSplash(
        const SettingsState(status: LoadStatus.loading, settingsRead: true),
      ),
      AppRoutes.onboardingPath,
    );
  });

  test('an install from before there was an introduction has not seen it', () {
    expect(
      AppSettings.fromMap(const <String, dynamic>{
        'reciterId': 'x',
      }).onboardingSeen,
      isFalse,
    );
    expect(
      AppSettings.fromMap(
        const AppSettings(onboardingSeen: true).toMap(),
      ).onboardingSeen,
      isTrue,
    );
  });
}
