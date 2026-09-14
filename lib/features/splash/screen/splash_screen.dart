import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/bootstrap.dart';
import '../../../core/constants/asset_paths.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// The launch animation: a camera push out of a cave mouth onto the plaza.
///
/// Two photographic plates, stacked. The vista sits behind; the cave sits in
/// front with its opening cut out as real alpha, so at rest the two read as one
/// photograph. Then both scale up — the cave much faster, so the rock rushes
/// past the viewer — and the cave fades out, leaving the vista filling the
/// frame with the wordmark over it.
///
/// ### Why the two plates line up
///
/// They are stored at different resolutions on purpose: the cave is 1224 x 2584
/// and the vista 1836 x 3876. The cave is smaller because it is dark, in
/// motion, and gone before the animation ends, so detail there is wasted bytes.
///
/// What makes the alignment work is that both plates describe the *same*
/// virtual frame — and they have byte-for-byte the same aspect ratio:
/// 1836 x 2584 == 1224 x 3876 == 4,744,224. Because of that, giving each plate
/// its own [BoxFit.cover] against the same box produces the same on-screen
/// rectangle for both, and the cave's alpha hole falls exactly over the
/// vista's real region.
///
/// [BoxFit.cover] per layer is deliberate, and it is the reason there is no
/// hand-rolled `screenWidth / 1836` base-scale arithmetic here. Scaling each
/// plate by its own width would align them too, but only on a screen whose
/// aspect ratio happens to match the plates' 0.4737 — on a taller 9:19.5 phone
/// a width-fit plate is shorter than the screen and leaves gaps top and
/// bottom. `cover` is what keeps both plates filling the frame at every aspect
/// ratio, and applying it *per layer* is what stops the cave rendering at
/// two-thirds size. A single shared scale across both plates is the mistake to
/// avoid, and this structure cannot express it.
///
/// `test/ui/splash_screen_test.dart` pins the aspect-ratio equality, because
/// it is the invariant the whole illusion rests on and a replacement plate at a
/// different ratio would break it silently.
class SplashScreen extends StatefulWidget {
  const SplashScreen({required this.onFinished, this.bootstrap, super.key});

  /// Called once, when the splash is done and the app should take over.
  final VoidCallback onFinished;

  /// Startup work to run alongside the animation. Defaults to
  /// [AppBootstrap.future]; injectable so a test can supply its own.
  final Future<void>? bootstrap;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // --- timeline ---------------------------------------------------------------

  static const Duration _total = Duration(milliseconds: 2400);

  /// The camera move occupies the first 74% of the timeline; the text arrives
  /// over the last 44%, overlapping it.
  static const double _camEnd = 0.74;

  static const double _sceneScaleTo = 1.70;
  static const double _caveScaleTo = 2.80;

  /// The cave's fade, in *camera* progress rather than raw time — it has to
  /// stay tied to the push, not to the clock.
  static const double _caveFadeFrom = 0.52;
  static const double _caveFadeTo = 0.82;

  static const double _textFrom = 0.56;
  static const double _textRiseDp = 26;

  /// The sun's slow breath: independent of the camera, so it keeps moving
  /// after the push settles.
  static const Duration _breathPeriod = Duration(milliseconds: 2200);

  /// However long startup takes, the splash stops blocking at this point. Past
  /// it the home screen shows its own loading state, which is honest — a
  /// splash that waits forever is just a hang with artwork.
  static const Duration _initCap = Duration(seconds: 5);

  /// Held 600 ms on the final frame when the platform asks for no animation.
  static const Duration _reducedMotionHold = Duration(milliseconds: 600);

  late final AnimationController _camera = AnimationController(
    vsync: this,
    duration: _total,
  );
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: _breathPeriod,
  );

  /// The cap, as a field so it is cancelled in [dispose] rather than firing
  /// into a dead route.
  Timer? _capTimer;

  final Completer<void> _animationDone = Completer<void>();
  bool _finishing = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Needs a context for the image cache, and must run before the controller
    // starts: animating an undecoded 1836 x 3876 plate hitches on frame one.
    if (!_started) {
      _started = true;
      _start();
    }
  }

  Future<void> _start() async {
    await _precachePlates();
    if (!mounted) return;

    final bool reducedMotion = MediaQuery.of(context).disableAnimations;

    if (reducedMotion) {
      // Straight to the end state: no push, no fade, text already in place.
      _camera.value = 1;
      if (!_animationDone.isCompleted) {
        Timer(_reducedMotionHold, () {
          if (mounted && !_animationDone.isCompleted) _animationDone.complete();
        });
      }
    } else {
      _breath.repeat();
      _camera.forward().whenComplete(() {
        if (!_animationDone.isCompleted) _animationDone.complete();
      });
    }

    await _waitThenFinish();
  }

  /// Both plates decoded before the first animated frame.
  ///
  /// Failures are swallowed on purpose: a missing plate should cost the
  /// animation its backdrop, not stop the app from starting. The asset audit
  /// is what guards their presence.
  Future<void> _precachePlates() async {
    for (final String path in <String>[
      AssetPaths.splashScene,
      AssetPaths.splashCave,
    ]) {
      try {
        await precacheImage(AssetImage(path), context);
      } catch (_) {
        // Ignored: see above.
      }
      if (!mounted) return;
    }
  }

  /// Finishes on whichever of [animation, startup] takes longer — capped.
  ///
  /// The cap bounds the *animation* side of that wait, not the startup side.
  /// Past it the splash stops waiting for a slow launch and lets the home
  /// screen show its own loading state, which is honest: a splash that waits
  /// forever is a hang with artwork over it.
  ///
  /// What the cap deliberately does **not** do is hand over before startup has
  /// finished. The home screen is built out of the service locator, so leaving
  /// early would not degrade gracefully — it would fail to build at all. If
  /// initialisation is genuinely stuck, the honest thing on screen is the
  /// splash, not a crash.
  Future<void> _waitThenFinish() async {
    final Future<void> startup = widget.bootstrap ?? AppBootstrap.future;

    final Completer<void> capped = Completer<void>();
    _capTimer = Timer(_initCap, () {
      if (!capped.isCompleted) capped.complete();
    });

    await Future.any<void>(<Future<void>>[
      Future.wait<void>(<Future<void>>[_animationDone.future, startup]),
      capped.future,
    ]);

    _capTimer?.cancel();
    _capTimer = null;

    // The one thing the cap cannot skip.
    await startup;
    if (!mounted) return;

    _finish();
  }

  void _finish() {
    if (_finishing || !mounted) return;
    _finishing = true;
    widget.onFinished();
  }

  /// Tap anywhere: jump to the final frame and leave.
  ///
  /// Works before the text has appeared, which is most of the animation, so it
  /// sets the controller to its end rather than waiting for it.
  void _skip() {
    if (_finishing) return;
    _camera.stop();
    _camera.value = 1;
    if (!_animationDone.isCompleted) _animationDone.complete();
    _finish();
  }

  @override
  void dispose() {
    _capTimer?.cancel();
    _camera.dispose();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _skip,
      // The whole frame is the target, including the parts of it that are
      // still pure black rock early on.
      behavior: HitTestBehavior.opaque,
      child: ColoredBox(
        // Frame 0's own colour, and the native splash's, so the handover from
        // the system splash to this one has nothing to show between them.
        color: AppColors.caveDark,
        child: AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[_camera, _breath]),
          builder: (BuildContext context, Widget? _) => _frame(context),
        ),
      ),
    );
  }

  Widget _frame(BuildContext context) {
    final double t = _camera.value;
    final double cam = Curves.easeInOutCubic.transform(
      math.min(1, t / _camEnd),
    );

    final double sceneScale = ui.lerpDouble(1, _sceneScaleTo, cam)!;
    final double caveScale = ui.lerpDouble(1, _caveScaleTo, cam)!;

    // Linear on the camera, not on time: the rock has to thin out as it passes
    // the viewer, whatever the clock is doing.
    final double caveOpacity =
        1 -
        ((cam - _caveFadeFrom) / (_caveFadeTo - _caveFadeFrom)).clamp(0.0, 1.0);

    final double textT = ((t - _textFrom) / (1 - _textFrom)).clamp(0.0, 1.0);
    final double textCurve = Curves.easeOutCubic.transform(textT);

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // z0 — the vista.
        RepaintBoundary(
          child: _Plate(asset: AssetPaths.splashScene, scale: sceneScale),
        ),

        // The sun, drawn rather than baked, so it can breathe and so it tracks
        // the camera. Above the vista and below the rock: it has to bloom
        // through the opening, not over the stone.
        RepaintBoundary(
          child: CustomPaint(
            painter: _SunBloomPainter(
              cam: cam,
              breath: _breath.isAnimating || _breath.value > 0
                  ? math.sin(_breath.value * 2 * math.pi)
                  : 0,
            ),
          ),
        ),

        // z1 — the rock. Zero opacity at the end, not near-zero: this is the
        // softest plate on screen and a lingering 2% reads as haze.
        if (caveOpacity > 0)
          RepaintBoundary(
            child: Opacity(
              opacity: caveOpacity,
              child: _Plate(asset: AssetPaths.splashCave, scale: caveScale),
            ),
          ),

        // The wordmark. Flutter text, not baked into a plate, so it stays
        // localizable and stays crisp at every density.
        _TextBlock(opacity: textCurve, rise: textCurve),
      ],
    );
  }
}

/// One photographic plate: covered, centred, scaled about its centre.
class _Plate extends StatelessWidget {
  const _Plate({required this.asset, required this.scale});

  final String asset;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: scale,
      // `cover` per plate is what keeps the two aligned at every aspect ratio;
      // see the note on SplashScreen.
      child: Image.asset(
        asset,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        width: double.infinity,
        height: double.infinity,
        // Decoration, not information: the splash says nothing a screen reader
        // needs, and the wordmark below is real text.
        excludeFromSemantics: true,
        // The plates are the frame; a fade-in here would fight the animation.
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

/// The sun bloom: white to transparent, tied to the camera, breathing slowly.
///
/// A painter rather than a `RadialGradient` decoration because the spec puts
/// the radius in units of *screen width*, and `RadialGradient.radius` is a
/// fraction of the shortest side — on a portrait phone those differ by nearly
/// half, which would put the bloom at the wrong size on every device.
class _SunBloomPainter extends CustomPainter {
  const _SunBloomPainter({required this.cam, required this.breath});

  final double cam;

  /// -1..1, a slow independent oscillation.
  final double breath;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset centre = Offset(
      size.width * 0.5,
      size.height * (0.40 - 0.03 * cam),
    );
    final double radius = size.width * (0.42 + 0.20 * cam);
    final double opacity = (0.06 + 0.05 * cam + 0.03 * breath).clamp(0.0, 1.0);
    if (radius <= 0 || opacity <= 0) return;

    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(centre, radius, <Color>[
          AppColors.splashBloom.withValues(alpha: opacity),
          AppColors.splashBloom.withValues(alpha: 0),
        ]),
    );
  }

  @override
  bool shouldRepaint(_SunBloomPainter old) =>
      old.cam != cam || old.breath != breath;
}

/// Name, hairline, slogan — placed as fractions of screen height so the block
/// sits with the plaza rather than with the bottom of the phone.
class _TextBlock extends StatelessWidget {
  const _TextBlock({required this.opacity, required this.rise});

  final double opacity;

  /// 0 → 1; the block travels [_SplashScreenState._textRiseDp] upward over it.
  final double rise;

  /// Holds the text over a bright, busy plaza.
  static const List<Shadow> _shadow = <Shadow>[
    Shadow(
      color: AppColors.splashTextShadow,
      offset: Offset(0, 2),
      blurRadius: 6,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (opacity <= 0) return const SizedBox.shrink();

    final double dy = (1 - rise) * _SplashScreenState._textRiseDp.h;

    return IgnorePointer(
      // The whole screen is one big skip target; the text must not eat taps.
      child: Opacity(
        opacity: opacity,
        child: Transform.translate(
          offset: Offset(0, dy),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) => Stack(
              children: <Widget>[
                _at(
                  c,
                  0.750,
                  Text(
                    LocaleKeys.appName.tr(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      // The UI Arabic face. The mushaf family is for ayat and
                      // must never appear here; `AppTextStyles.uiFontFamily` is
                      // the only family this file names.
                      fontFamily: AppTextStyles.uiFontFamily,
                      fontSize: 35.sp,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                      decoration: TextDecoration.none,
                      color: AppColors.splashName,
                      // shadows: _shadow,
                    ),
                  ),
                ),
                // _at(
                //   c,
                //   0.757,
                //   Center(
                //     // Grows outward from the centre on the same curve as the
                //     // text, so the rule draws itself rather than appearing.
                //     child: SizedBox(
                //       width: 130.w * rise,
                //       height: 2.h,
                //       child: ColoredBox(
                //         color: AppColors.splashHairline.withValues(alpha: 0.82),
                //       ),
                //     ),
                //   ),
                // ),
                _at(
                  c,
                  0.808,
                  Text(
                    LocaleKeys.appSlogan.tr(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTextStyles.uiFontFamily,
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                      color: AppColors.splashSlogan,
                      decoration: TextDecoration.none,

                      shadows: _shadow,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Centres [child] on the line at [fraction] of the available height.
  ///
  /// Deliberately not `Positioned(top:)` with a fixed height: the text has to
  /// be free to grow downward at a large system font scale instead of being
  /// clipped to a band.
  Widget _at(BoxConstraints c, double fraction, Widget child) => Positioned(
    top: c.maxHeight * fraction,
    left: 0,
    right: 0,
    child: Align(alignment: Alignment.topCenter, child: child),
  );
}
