import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Hands the window's own frame — the part Windows draws, not Flutter — the
/// colours of the theme inside it.
///
/// Without this the title bar follows the *system* theme while the app
/// follows the reader's setting, so an app set to dark on a light Windows
/// wears a white cap: the one detail that says "this is not a Windows app"
/// before anything else is read. The runner already picks up the system
/// theme on its own; this overrides it with the app's.
///
/// Windows only, and quiet everywhere else: macOS and Linux draw their own
/// frames and have no such channel, so [follow] returns without a call. It is
/// not a network call and not a plugin — a `MethodChannel` to this app's own
/// runner, the same way the admin tool reaches `NSOpenPanel` (CLAUDE.md A.7).
abstract final class WindowChrome {
  @visibleForTesting
  static const MethodChannel channel = MethodChannel('mirqat/window');

  /// Stands in for the platform check, so the contract below can be tested
  /// somewhere other than on Windows.
  @visibleForTesting
  static bool? debugSupportedOverride;

  /// Whether this platform has a frame to colour.
  static bool get supported =>
      debugSupportedOverride ?? (!kIsWeb && Platform.isWindows);

  /// The last values sent, so a rebuild — and there is one on every window
  /// resize — does not cross the channel again for nothing.
  static Brightness? _brightness;
  static Color? _surface;

  /// Paints the frame to match [theme].
  ///
  /// The caption takes the colour the page behind it has, so the window reads
  /// as one piece from its top edge down. Failures are swallowed: an older
  /// Windows that does not know these attributes must leave the app running,
  /// not stop it (the frame simply stays as Windows drew it).
  static Future<void> follow(ThemeData theme) async {
    if (!supported) return;
    final Brightness brightness = theme.brightness;
    final Color surface = theme.scaffoldBackgroundColor;
    if (brightness == _brightness && surface == _surface) return;
    _brightness = brightness;
    _surface = surface;

    try {
      await channel.invokeMethod<void>('applyTheme', <String, Object>{
        'dark': brightness == Brightness.dark,
        // ARGB as an int, which is what DwmSetWindowAttribute wants
        // rearranged on the other side — the conversion belongs with the
        // Win32 call, not here.
        'caption': surface.toARGB32(),
        'text': theme.colorScheme.onSurface.toARGB32(),
        'border': theme.colorScheme.outline.toARGB32(),
      });
    } on PlatformException {
      // The window kept its own colours. Nothing a reader can do, and
      // nothing worth a dialog (A.2 rule 3's spirit: degrade quietly).
    } on MissingPluginException {
      // A runner older than this channel. Same answer.
    }
  }

  /// Forgets what was last sent, so the next [follow] speaks again, and
  /// puts the platform check back.
  @visibleForTesting
  static void reset() {
    _brightness = null;
    _surface = null;
    debugSupportedOverride = null;
  }
}
