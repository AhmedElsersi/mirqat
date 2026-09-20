import 'package:url_launcher/url_launcher.dart';

/// Hands an address to whatever on the device opens it: the mail app, the
/// browser, WhatsApp.
///
/// Not a network call of the app's own — the app fetches nothing here, it
/// asks the system to take the reader elsewhere — so CLAUDE.md A.2 rule 3 is
/// untouched. Behind a class so that a test can stand in for the device.
class LinkOpener {
  const LinkOpener();

  /// False when nothing on the device would take [uri], or the attempt threw.
  /// Never an exception: a link that will not open is a line of text on the
  /// screen, not a crash.
  Future<bool> open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      return false;
    }
  }
}
