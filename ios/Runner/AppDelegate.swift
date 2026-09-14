import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Matches the channel name in MainActivity.kt and KeepAwakeService.
  private static let keepAwakeChannel = "com.mirqat.app/keep_awake"

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
  }
}
