import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../data/models/reciter.dart';

/// The reciter's photograph, circular, at whatever diameter the caller needs.
///
/// Three things must never happen here, and all three are the same failure
/// wearing different clothes: a red error box, a thrown exception, and an empty
/// hole where a face should be. A portrait is decoration around a name — the
/// name is the information — so every path that cannot produce an image
/// produces the fallback instead:
///
///   * [Reciter.imagePath] is null (no photo catalogued),
///   * the asset is declared but missing from the bundle,
///   * the bytes are there but will not decode.
///
/// The first is a plain null check; the other two arrive asynchronously, after
/// the widget has already been laid out, which is why [Image.asset]'s
/// `errorBuilder` is wired rather than trusted to be unnecessary.
class ReciterAvatar extends StatelessWidget {
  const ReciterAvatar({required this.reciter, required this.diameter, super.key});

  final Reciter reciter;

  /// Side length of the circle, in design pixels. `.r` is applied here, so
  /// callers pass a plain number.
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final double size = diameter.r;
    final String? path = reciter.imagePath;

    return SizedBox.square(
      dimension: size,
      child: ClipOval(
        child: path == null
            ? _Fallback(reciter: reciter, size: size)
            : Image.asset(
                path,
                width: size,
                height: size,
                fit: BoxFit.cover,
                // A portrait is not information a screen reader needs read
                // aloud: the name it sits beside already carries it.
                excludeFromSemantics: true,
                errorBuilder: (BuildContext context, Object error, StackTrace? _) =>
                    _Fallback(reciter: reciter, size: size),
              ),
      ),
    );
  }
}

/// Neutral stand-in: the reciter's initial on a themed ground.
///
/// The initial comes from the Arabic name, which the catalog always has, so
/// this never renders blank. It is deliberately not a generic silhouette
/// icon — an initial tells two reciters apart, and a silhouette does not.
class _Fallback extends StatelessWidget {
  const _Fallback({required this.reciter, required this.size});

  final Reciter reciter;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String initial = reciter.nameAr.characters.isEmpty
        ? ''
        : reciter.nameAr.characters.first;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: theme.colorScheme.surfaceContainerHighest,
      child: initial.isEmpty
          ? Icon(
              Icons.person_outline,
              size: size * 0.55,
              color: theme.colorScheme.onSurfaceVariant,
            )
          : Text(
              initial,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                // Tied to the circle rather than the text scale: the glyph has
                // to stay inside a fixed-diameter clip at any system font size.
                fontSize: size * 0.42,
                height: 1,
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}
