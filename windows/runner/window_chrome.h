#ifndef RUNNER_WINDOW_CHROME_H_
#define RUNNER_WINDOW_CHROME_H_

#include <windows.h>

// Paints the part of the window Windows draws — the caption, its text and the
// frame's border — in the colours of the Flutter theme inside it, and tells
// the frame whether it is a light or a dark app.
//
// Why this exists: the title bar follows the *system* theme by default, so an
// app set to dark on a light Windows wears a white cap. That seam is the first
// thing that says an app is not a Windows app.
//
// Everything here is the Desktop Window Manager's, through attributes
// documented for Windows 11 build 22000 and later. On an older Windows the
// calls fail and the frame simply stays as Windows drew it: there is nothing
// for a reader to do about it and nothing worth interrupting them for, which
// is why no result is reported upward.
namespace window_chrome {

// |caption|, |text| and |border| are 0xAARRGGBB, as Flutter writes a colour.
// The alpha is ignored: a window frame is opaque.
void Apply(HWND window,
           bool dark,
           uint32_t caption,
           uint32_t text,
           uint32_t border);

}  // namespace window_chrome

#endif  // RUNNER_WINDOW_CHROME_H_
