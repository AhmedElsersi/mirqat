import 'package:flutter/services.dart';

/// Asks macOS for a recording to split.
///
/// A platform channel into `NSOpenPanel` rather than a package: `file_picker`
/// is not on the approved list (CLAUDE.md A.4), and the panel is a few lines of
/// Swift in `macos/Runner/MainFlutterWindow.swift`. An interface so the cubit
/// can be tested without a window.
abstract class AdminFilePicker {
  /// The chosen file's path, or null when the operator cancelled.
  ///
  /// Throws [MissingPluginException] where the channel is not there, which is
  /// every platform but macOS — and macOS is the only one this tool runs on.
  Future<String?> pickRecording();

  /// A reciter's portrait, or null when the operator cancelled.
  Future<String?> pickImage();

  /// A file of links — a QUL recitation export — or null when the operator
  /// cancelled.
  Future<String?> pickLinkFile();
}

class NativeAdminFilePicker implements AdminFilePicker {
  const NativeAdminFilePicker();

  static const MethodChannel _channel = MethodChannel('mirqat/admin_files');

  @override
  Future<String?> pickRecording() =>
      _channel.invokeMethod<String>('pickRecording');

  @override
  Future<String?> pickImage() => _channel.invokeMethod<String>('pickImage');

  @override
  Future<String?> pickLinkFile() =>
      _channel.invokeMethod<String>('pickLinkFile');
}
