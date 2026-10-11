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

/// The narrowest window that lies open at two facing pages, the way a printed
/// mushaf does.
///
/// Below it the window turns one page at a time. The number is not taste: a
/// mushaf line sets its own font size from the width of the page it is
/// printed on (A.3), so two pages in a 900-pixel window would be two
/// 450-pixel pages and the script would come out half the size the same
/// window shows it at now. At 1000 each page is 500 wide — a printed page's
/// proportions at a size that is still read rather than squinted at.
const double kDesktopSpreadWidth = 1000;

/// The widest an open spread is drawn: two pages at [kDesktopPageWidth], and
/// no wider however far the window is dragged.
const double kDesktopSpreadMaxWidth = 2 * kDesktopPageWidth;

/// Whether a window [width] wide lies open at two facing pages. False on a
/// phone whatever its width: a tablet held in two hands is not a book on a
/// desk, and its pages are turned with a thumb.
bool spreadFits(double width) => isDesktop && width >= kDesktopSpreadWidth;

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
