import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Matches the channel name in MainActivity.kt and KeepAwakeService.
  private static let keepAwakeChannel = "com.mirqat.app/keep_awake"

  /// Matches the channel name in AudioStorage.
  private static let storageChannel = "mirqat/storage"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // A memorization session is long and mostly hands-off, so the screen must
    // not dim mid-recitation. Done with the idle timer rather than a package,
    // keeping the approved dependency list untouched.
    let channel = FlutterMethodChannel(
      name: AppDelegate.keepAwakeChannel,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "setKeepAwake":
        UIApplication.shared.isIdleTimerDisabled = (call.arguments as? Bool) ?? false
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Downloaded recitations are re-downloadable content, and Apple rejects
    // apps that back such content up to iCloud. The audio directory therefore
    // carries the do-not-back-up flag. It lives under Application Support
    // rather than Caches on purpose: iOS may purge Caches mid-session, which
    // would take a surah out from under a running session.
    let storage = FlutterMethodChannel(
      name: AppDelegate.storageChannel,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    storage.setMethodCallHandler { call, result in
      switch call.method {
      case "excludeFromBackup":
        guard
          let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String
        else {
          result(
            FlutterError(
              code: "bad_arguments",
              message: "excludeFromBackup needs a \"path\".",
              details: nil
            )
          )
          return
        }
        var url = URL(fileURLWithPath: path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
          try url.setResourceValues(values)
          result(nil)
        } catch {
          result(
            FlutterError(
              code: "exclude_failed",
              message: error.localizedDescription,
              details: path
            )
          )
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
