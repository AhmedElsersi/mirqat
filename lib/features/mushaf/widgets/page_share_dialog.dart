import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../cubit/mushaf_page.dart';
import 'ayah_share_dialog.dart' show shareBoundary;
import 'mushaf_page_view.dart';

/// A whole mushaf page as an image: the page drawn exactly as the reading
/// view draws it — the same words from `quran.db`, the same lines, the same
/// frame with its surah, juz and page number — with nothing of the reader's
/// own on it (no tint, no mark, nothing covered).
///
/// On the light page whatever the app's theme, as the shared ayah is: an
/// image that leaves the app should look like a page. Laid out at a printed
/// page's proportions, tall enough that every page fits without scrolling,
/// so what is captured is always the page whole.
class PageShareCard extends StatelessWidget {
  const PageShareCard({
    required this.page,
    required this.linesPerFullPage,
    super.key,
  });

  final MushafPage page;
  final int linesPerFullPage;

  /// The card's size: a phone page's width, and room enough below it that
  /// the fullest page is drawn at its printed size without scrolling.
  static Size get size => Size(360.w, 680.w);

  @override
  Widget build(BuildContext context) => Theme(
    data: AppTheme.light,
    child: Container(
      width: size.width,
      height: size.height,
      color: AppColors.cream,
      child: MushafPageView(
        page: page,
        linesPerFullPage: linesPerFullPage,
        highlighted: null,
        selected: null,
        ribbon: false,
        stumbled: const {},
        onWordLongPress: (_) {},
      ),
    ),
  );
}

/// Shows the page a reader asked to share, and shares it.
///
/// Like the ayah's dialog, the card is laid out at full size inside a
/// [RepaintBoundary] and only displayed scaled down, so the capture is the
/// whole page at full resolution.
class PageShareDialog extends StatefulWidget {
  const PageShareDialog({
    required this.page,
    required this.linesPerFullPage,
    super.key,
  });

  final MushafPage page;
  final int linesPerFullPage;

  @override
  State<PageShareDialog> createState() => _PageShareDialogState();
}

class _PageShareDialogState extends State<PageShareDialog> {
  final GlobalKey _card = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    final String caption =
        '${LocaleKeys.mushafPage.tr(args: <String>[widget.page.number.toLocalisedString()])} — ${LocaleKeys.appName.tr()}';
    final bool shared = await shareBoundary(
      _card,
      filename: 'page_${widget.page.number}.png',
      caption: caption,
    );
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
                child: PageShareCard(
                  page: widget.page,
                  linesPerFullPage: widget.linesPerFullPage,
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
