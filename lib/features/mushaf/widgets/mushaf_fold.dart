import 'package:flutter/material.dart';

/// The fold between two facing pages of an open mushaf.
///
/// A printed mushaf lying open is not two pages side by side: the paper falls
/// away into the binding, so the inner edges sit in a soft shadow with the
/// crease itself a hair darker than either page. That is all this draws — a
/// gradient that is deepest at the centre and gone by either page's edge, and
/// a one-pixel crease down the middle.
///
/// It carries no text and belongs to neither page, so it takes [onTap] and
/// hands it the same meaning a tap on a page has: show or hide the reading
/// bar. Without that the strip between the pages would be the one place on
/// the screen where a tap did nothing.
class MushafFold extends StatelessWidget {
  const MushafFold({this.onTap, super.key});

  /// How wide the fold is drawn. Narrow enough that neither page loses a
  /// readable amount of width to it, wide enough for the shadow to read as
  /// depth rather than as a rule between two boxes.
  static const double width = 22;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    // The shadow in the gutter, in the theme's own ink: strongest in the
    // crease and nothing at all where the page lies flat again.
    final Color ink = colors.shadow;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            // Begin and end rather than start and end: the fold is symmetric,
            // so it reads the same in either direction and needs no RTL.
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: <Color>[
              ink.withValues(alpha: 0),
              ink.withValues(alpha: 0.05),
              ink.withValues(alpha: 0.14),
              ink.withValues(alpha: 0.05),
              ink.withValues(alpha: 0),
            ],
            stops: const <double>[0, 0.34, 0.5, 0.66, 1],
          ),
        ),
        child: Center(
          child: SizedBox(
            width: 1,
            child: ColoredBox(color: colors.outline.withValues(alpha: 0.5)),
          ),
        ),
      ),
    );
  }
}

/// The empty half of a leaf: where a surah or a juz ends on a right-hand
/// page, nothing is printed facing it. Bare page, and a tap on it means what
/// a tap on a page means.
class MushafBlankPage extends StatelessWidget {
  const MushafBlankPage({this.onTap, super.key});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: const SizedBox.expand(),
  );
}
