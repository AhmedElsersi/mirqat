import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps the screen on during a session.
///
/// A memorization session runs for minutes with the phone put down, so the
/// display dimming mid-recitation is a real interruption. Implemented over a
/// platform channel rather than a package, so the approved dependency list is
/// untouched (CLAUDE.md A.4): Android sets FLAG_KEEP_SCREEN_ON, iOS disables
/// the idle timer.
class KeepAwakeService {
  const KeepAwakeService([
    this._channel = const MethodChannel('com.mirqat.app/keep_awake'),
  ]);

  final MethodChannel _channel;

  /// Turns the wake lock on or off. Platforms without a handler are a no-op
  /// rather than an error — the toggle is a convenience, never a blocker.
  Future<void> setEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setKeepAwake', enabled);
    } on MissingPluginException {
      // No handler on this platform (desktop, web, tests).
    } on PlatformException catch (e) {
      debugPrint('keep-awake toggle failed: ${e.message}');
    }
  }
}
