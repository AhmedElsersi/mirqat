import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../data/models/reciter.dart';
import '../../services/reciter_image_cache.dart';
import '../di/injection.dart';

/// The reciter's photograph, circular, at whatever diameter the caller needs.
///
/// Three things must never happen here, and all three are the same failure
/// wearing different clothes: a red error box, a thrown exception, and an empty
/// hole where a face should be. A portrait is decoration around a name — the
/// name is the information — so every path that cannot produce an image
/// produces the fallback instead:
///
///   * the reciter has no portrait at all, bundled or remote,
///   * an asset is declared but missing from the bundle,
///   * a remote portrait has not been fetched yet, or cannot be,
///   * the bytes are there but will not decode.
///
/// Three sources, in order: a bundled asset, a portrait cached on disk from
/// the CDN, and the initial. The bundled one wins because it costs no request
/// and is there on first run; the cached one is what lets a reciter be added
/// to the manifest without shipping an app version.
class ReciterAvatar extends StatelessWidget {
  const ReciterAvatar({
    required this.reciter,
    required this.diameter,
    super.key,
  });

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
        child: path != null
            ? Image.asset(
                path,
                width: size,
                height: size,
                fit: BoxFit.cover,
                // A portrait is not information a screen reader needs read
                // aloud: the name it sits beside already carries it.
                excludeFromSemantics: true,
                errorBuilder:
                    (BuildContext context, Object error, StackTrace? _) =>
                        _Fallback(reciter: reciter, size: size),
              )
            : _RemotePortrait(reciter: reciter, size: size),
      ),
    );
  }
}

/// A portrait fetched from the CDN and kept on disk.
///
/// The initial is shown until the file is there, and stays if it never is —
/// no spinner. A circle that flickers a progress indicator on every list row
/// is noisier than a letter that quietly becomes a face.
class _RemotePortrait extends StatefulWidget {
  const _RemotePortrait({required this.reciter, required this.size});

  final Reciter reciter;
  final double size;

  @override
  State<_RemotePortrait> createState() => _RemotePortraitState();
}

class _RemotePortraitState extends State<_RemotePortrait> {
  File? _file;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_RemotePortrait oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reciter.imageUrl != widget.reciter.imageUrl) _load();
  }

  Future<void> _load() async {
    if (widget.reciter.imageUrl == null) return;
    // Registered lazily rather than injected: this widget is built deep inside
    // lists that have no reason to know about a cache.
    if (!sl.isRegistered<ReciterImageCache>()) return;

    final File? file = await sl<ReciterImageCache>().imageFor(widget.reciter);
    if (mounted && file != null) setState(() => _file = file);
  }

  @override
  Widget build(BuildContext context) {
    final File? file = _file;
    if (file == null) {
      return _Fallback(reciter: widget.reciter, size: widget.size);
    }
    return Image.file(
      file,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.cover,
      excludeFromSemantics: true,
      errorBuilder: (BuildContext context, Object error, StackTrace? _) =>
          _Fallback(reciter: widget.reciter, size: widget.size),
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
