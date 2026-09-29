import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// What changes when the app runs in a window on a desk rather than in a
/// hand.
///
/// The phone layout is scaled from a phone-sized design (CLAUDE.md A.3), and
/// a 1400-pixel window scaled from a 375-pixel design is a phone screen
/// blown up four times. On a desktop the design *is* the window, so every
/// `.w`, `.h` and `.sp` is one logical pixel — and what a phone fills edge to
/// edge is held to a column a desk can read: the mushaf page at the width of
/// a printed one, the lists at the width of a page of text.
///
/// Decided from [defaultTargetPlatform], not `dart:io`, so that a test run
/// on a Mac still lays the phone out as a phone.
bool get isDesktop =>
    !kIsWeb &&
    switch (defaultTargetPlatform) {
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux => true,
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => false,
    };

/// The widest a list or a form is drawn on a desktop, in logical pixels.
const double kDesktopContentWidth = 760;

/// The widest a mushaf page is drawn on a desktop: a printed page's width at
/// a comfortable reading size, with its frame.
const double kDesktopPageWidth = 640;

/// [child] at the width a desk can read, centred; on a phone, as it is.
class DesktopWidth extends StatelessWidget {
  const DesktopWidth({
    required this.child,
    this.maxWidth = kDesktopContentWidth,
    super.key,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => isDesktop
      ? Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: child,
          ),
        )
      : child;
}

/// Scrolling that a mouse can drag as well as a finger, so the mushaf's
/// pages turn under a mouse and the lists move under one. Harmless on a
/// phone, where there is no mouse to drag with.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.unknown,
  };
}
