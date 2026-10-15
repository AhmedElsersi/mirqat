import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The admin panel's text size, under the operator's hand.
///
/// A workbench is read at whatever distance the operator sits, and a timecode
/// or an ayah too small to check is a boundary published unchecked. The scope
/// multiplies every piece of text in the tool — labels, timecodes, and the
/// ayah beside each segment alike — through [MediaQuery]'s `textScaler`, so
/// no widget below needs to know. The ayah's *size* only: the bytes reaching
/// the renderer are `quran.db`'s, untouched (CLAUDE.md A.2 rule 1).
///
/// ⌘+ and ⌘− step it, ⌘0 puts it back, and the main screen's app bar carries
/// the same three moves as buttons. The choice lives for the run: this is a
/// workbench, not a product, and a preference store is more tool than the
/// job needs.
class AdminTextScaleScope extends StatefulWidget {
  const AdminTextScaleScope({required this.child, super.key});

  final Widget child;

  @override
  State<AdminTextScaleScope> createState() => _AdminTextScaleScopeState();
}

class _AdminTextScaleScopeState extends State<AdminTextScaleScope> {
  // Tenths rather than a double, so a hundred steps cannot drift and the
  // percent shown is always exact.
  int _tenths = 10;

  void _set(int tenths) => setState(
    () => _tenths = tenths.clamp(
      AdminTextScale.minTenths,
      AdminTextScale.maxTenths,
    ),
  );

  @override
  Widget build(BuildContext context) {
    // The system's accessibility setting still counts: ours multiplies it
    // rather than silently writing over it. Measured at a body size, which
    // is exact for the linear scaling a desktop uses.
    final double system = MediaQuery.textScalerOf(context).scale(14) / 14;

    return AdminTextScale(
      tenths: _tenths,
      setTenths: _set,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.equal, meta: true): () =>
              _set(_tenths + 1),
          const SingleActivator(
            LogicalKeyboardKey.equal,
            meta: true,
            shift: true,
          ): () =>
              _set(_tenths + 1),
          const SingleActivator(LogicalKeyboardKey.numpadAdd, meta: true): () =>
              _set(_tenths + 1),
          const SingleActivator(LogicalKeyboardKey.minus, meta: true): () =>
              _set(_tenths - 1),
          const SingleActivator(
            LogicalKeyboardKey.numpadSubtract,
            meta: true,
          ): () =>
              _set(_tenths - 1),
          const SingleActivator(LogicalKeyboardKey.digit0, meta: true): () =>
              _set(10),
        },
        // Autofocus so the shortcuts work before anything is clicked; a
        // field the operator focuses later takes typing, while ⌘-chords
        // bubble up here untouched.
        child: Focus(
          autofocus: true,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(system * _tenths / 10)),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// What the scope publishes down the tree: the current size and the three
/// moves. Widgets reach it with [AdminTextScale.of]; a tree built without
/// the scope — a bare screen in a test — gets null and shows no control.
class AdminTextScale extends InheritedWidget {
  const AdminTextScale({
    required this.tenths,
    required this.setTenths,
    required super.child,
    super.key,
  });

  /// 10 is the design size; 8 is as small as stays readable at all, and
  /// past 20 the review list holds one row.
  static const int minTenths = 8;
  static const int maxTenths = 20;

  final int tenths;
  final ValueChanged<int> setTenths;

  static AdminTextScale? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AdminTextScale>();

  double get scale => tenths / 10;

  int get percent => tenths * 10;

  bool get canIncrease => tenths < maxTenths;

  bool get canDecrease => tenths > minTenths;

  bool get isDefault => tenths == 10;

  void increase() => setTenths(tenths + 1);

  void decrease() => setTenths(tenths - 1);

  void reset() => setTenths(10);

  @override
  bool updateShouldNotify(AdminTextScale oldWidget) =>
      oldWidget.tenths != tenths;
}
