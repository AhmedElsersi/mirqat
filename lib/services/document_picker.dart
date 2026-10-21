import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What came of asking the reader for a file.
sealed class PickedText {
  const PickedText();
}

/// The file's contents, read whole as UTF-8.
class Picked extends PickedText {
  const Picked(this.text);

  final String text;
}

/// The reader closed the picker without choosing.
class PickCancelled extends PickedText {
  const PickCancelled();
}

/// A file was chosen and could not be read.
class PickFailed extends PickedText {
  const PickFailed();
}

/// The system's own file picker, over a platform channel rather than a
/// package — the approved dependency list is untouched (CLAUDE.md A.4), the
/// same way [ShareService] and the admin tool's file panel are.
///
/// Android only: since Android 11 the Files app cannot reach an app's own
/// folder, so a copy saved to Downloads or Drive has to be fetched by the
/// app itself. On iOS the app's folder is in the Files app, and a copy is
/// put there to be read (Info.plist's UIFileSharingEnabled).
class DocumentPicker {
  const DocumentPicker([
    this._channel = const MethodChannel('com.mirqat.app/files'),
  ]);

  final MethodChannel _channel;

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<PickedText> pickText() async {
    try {
      final String? text = await _channel.invokeMethod<String>('pickText');
      return text == null ? const PickCancelled() : Picked(text);
    } on MissingPluginException {
      return const PickCancelled();
    } on PlatformException catch (e) {
      debugPrint('pick failed: ${e.message}');
      return const PickFailed();
    }
  }
}
