import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Matches the channel name in MainActivity.kt and KeepAwakeService.
  private static let keepAwakeChannel = "com.mirqat.app/keep_awake"

  /// Matches the channel name in AudioStorage.
  private static let storageChannel = "mirqat/storage"

  /// Matches the channel name in ShareService.
  private static let shareChannel = "com.mirqat.app/share"

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

    // A long-pressed ayah shared as an image: the file ShareService wrote is
    // handed to the system share sheet. Done with UIActivityViewController
    // rather than a package, keeping the approved dependency list untouched
    // (CLAUDE.md A.4). Nothing is uploaded by the app itself.
    let share = FlutterMethodChannel(
      name: AppDelegate.shareChannel,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    share.setMethodCallHandler { call, result in
      switch call.method {
      case "shareFile":
        guard
          let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String
        else {
          result(
            FlutterError(
              code: "bad_arguments",
              message: "shareFile needs a \"path\".",
              details: nil
            )
          )
          return
        }
        var items: [Any] = [URL(fileURLWithPath: path)]
        if let text = arguments["text"] as? String {
          items.append(text)
        }
        let scenes = UIApplication.shared.connectedScenes
          .compactMap { $0 as? UIWindowScene }
        let window =
          scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
          ?? scenes.first?.windows.first
        guard let root = window?.rootViewController else {
          result(
            FlutterError(
              code: "no_window",
              message: "No window to present the share sheet from.",
              details: nil
            )
          )
          return
        }
        let activity = UIActivityViewController(
          activityItems: items,
          applicationActivities: nil
        )
        // On an iPad the sheet is a popover and must be anchored, or UIKit
        // throws. Centred with no arrow: the press that asked for it is long
        // gone from the screen by now.
        if let popover = activity.popoverPresentationController {
          popover.sourceView = root.view
          popover.sourceRect = CGRect(
            x: root.view.bounds.midX,
            y: root.view.bounds.midY,
            width: 0,
            height: 0
          )
          popover.permittedArrowDirections = []
        }
        root.present(activity, animated: true)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
