import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/di/injection.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ayah_text.dart';
import '../../../core/widgets/islamic_frame.dart';
import '../../../data/models/ayah.dart';
import '../../../data/models/surah.dart';
import '../../../services/share_service.dart';

/// The image a shared ayah becomes: the verbatim text inside the illuminated
/// frame, the surah and ayah named in the frame's own plaques, the app's name
/// at its foot.
///
/// Always drawn on the light page — cream, forest, gold — whatever theme the
/// app is in: the image leaves the app, and a shared page should look like a
/// page, not like a screenshot of someone's dark mode. The text itself is
/// [AyahText], byte-for-byte from `quran.db`, wrapped and never truncated
/// (CLAUDE.md A.2 rules 1 and 7); a long ayah simply makes a taller page.
class AyahShareCard extends StatelessWidget {
  const AyahShareCard({required this.ayah, required this.surahName, super.key});

  final Ayah ayah;

  /// The surah's name in the reader's language — a label, like the frame's
  /// other plaques.
  final String surahName;

  /// The text's size on the card. A label-free choice by length alone, the
  /// way a calligrapher sizes a panel to its words: nothing surah-specific
  /// (A.2 rule 2), and only presentation — the bytes are untouched.
  static double fontFor(String text) {
    final int length = text.length;
    if (length <= 250) return 24;
    if (length <= 500) return 20;
    if (length <= 900) return 17;
    return 14;
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: AppTheme.light,
    child: Container(
      width: 360.w,
      color: AppColors.cream,
      padding: EdgeInsetsDirectional.all(10.r),
      child: IslamicFrame(
        labels: FrameLabels(
          topStart: LocaleKeys.mushafSurahLabel.tr(args: <String>[surahName]),
          topEnd: LocaleKeys.commonAyahNumber.tr(
            args: <String>[ayah.number.toLocalisedString()],
          ),
          bottom: LocaleKeys.appName.tr(),
        ),
        // The full width of the card, whatever the ayah's length. The frame
        // lays its child out loosely, so a short ayah would otherwise shrink
        // the frame to the width of its words, pushed to one side, with the
        // plaques — laid out for the whole card — hanging off its edge.
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: EdgeInsetsDirectional.symmetric(
              horizontal: 8.w,
              vertical: 18.h,
            ),
            child: Center(
              child: AyahText.flowing(
                ayahs: <FlowingAyah>[
                  FlowingAyah(number: ayah.number, text: ayah.text),
                ],
                fontSize: fontFor(ayah.text),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Shows the card a long-pressed ayah would be shared as, and shares it.
///
/// The card is laid out at its full size inside a [RepaintBoundary] and only
/// *displayed* scaled down to fit the dialog, so what is captured is always
/// the whole page at full resolution — a scrolling preview would capture only
/// what happened to be on screen.
class AyahShareDialog extends StatefulWidget {
  const AyahShareDialog({required this.ayah, required this.surah, super.key});

  final Ayah ayah;
  final Surah surah;

  @override
  State<AyahShareDialog> createState() => _AyahShareDialogState();
}

class _AyahShareDialogState extends State<AyahShareDialog> {
  final GlobalKey _card = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);

    final String caption =
        '${LocaleKeys.mushafAyahReference.tr(args: <String>[_surahName(context), widget.ayah.number.toLocalisedString()])} — ${LocaleKeys.appName.tr()}';
    final bool shared = await _captureAndShare(caption);

    if (!mounted) return;
    if (shared) {
      Navigator.of(context).pop();
    } else {
      setState(() => _sharing = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(LocaleKeys.commonError.tr())));
    }
  }

  Future<bool> _captureAndShare(String caption) async {
    final RenderObject? render = _card.currentContext?.findRenderObject();
    if (render is! RenderRepaintBoundary) return false;

    // 3x the card's logical size: crisp on any feed the image lands in.
    final ui.Image image = await render.toImage(pixelRatio: 3);
    try {
      final ByteData? png = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (png == null) return false;
      return sl<ShareService>().shareImage(
        png.buffer.asUint8List(),
        filename: 'ayah_${widget.ayah.surahNumber}_${widget.ayah.number}.png',
        text: caption,
      );
    } finally {
      image.dispose();
    }
  }

  String _surahName(BuildContext context) => context.locale.languageCode == 'ar'
      ? widget.surah.nameAr
      : widget.surah.nameEn;

  @override
  Widget build(BuildContext context) => Dialog(
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: EdgeInsetsDirectional.all(12.r),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: RepaintBoundary(
                key: _card,
                child: AyahShareCard(
                  ayah: widget.ayah,
                  surahName: _surahName(context),
                ),
              ),
            ),
          ),
          SizedBox(height: 8.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              TextButton(
                onPressed: _sharing ? null : () => Navigator.of(context).pop(),
                child: Text(LocaleKeys.commonCancel.tr()),
              ),
              SizedBox(width: 8.w),
              FilledButton.icon(
                onPressed: _sharing ? null : _share,
                icon: _sharing
                    ? SizedBox.square(
                        dimension: 16.r,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.adaptive.share),
                label: Text(LocaleKeys.mushafShare.tr()),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
