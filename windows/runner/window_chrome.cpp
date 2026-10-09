#include "window_chrome.h"

#include <dwmapi.h>

#include <cstdint>

namespace {

// Redefined when the build machine's Windows SDK predates 10.0.22000.0, the
// same way win32_window.cpp redefines the dark-mode attribute. The values are
// the documented members of DWMWINDOWATTRIBUTE.
// See:
// https://learn.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif
#ifndef DWMWA_WINDOW_CORNER_PREFERENCE
#define DWMWA_WINDOW_CORNER_PREFERENCE 33
#endif
#ifndef DWMWA_BORDER_COLOR
#define DWMWA_BORDER_COLOR 34
#endif
#ifndef DWMWA_CAPTION_COLOR
#define DWMWA_CAPTION_COLOR 35
#endif
#ifndef DWMWA_TEXT_COLOR
#define DWMWA_TEXT_COLOR 36
#endif

// DWMWCP_ROUND: round the corners as Windows 11 rounds every other top-level
// window. Already the default; set so the frame cannot drift from the 8px
// corner the rest of the app is drawn to.
constexpr DWORD kRoundedCorners = 2;

// Flutter writes a colour as 0xAARRGGBB; a COLORREF is 0x00BBGGRR. The swap
// belongs here, beside the call that needs it, rather than in Dart.
COLORREF ToColorRef(uint32_t argb) {
  return RGB((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF);
}

}  // namespace

namespace window_chrome {

void Apply(HWND window,
           bool dark,
           uint32_t caption,
           uint32_t text,
           uint32_t border) {
  if (window == nullptr) {
    return;
  }

  // Dark mode first: it decides how Windows draws the caption's own buttons
  // (minimise, maximise, close), which the colours below do not touch.
  BOOL use_dark_mode = dark ? TRUE : FALSE;
  DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE, &use_dark_mode,
                        sizeof(use_dark_mode));

  COLORREF caption_color = ToColorRef(caption);
  DwmSetWindowAttribute(window, DWMWA_CAPTION_COLOR, &caption_color,
                        sizeof(caption_color));

  COLORREF text_color = ToColorRef(text);
  DwmSetWindowAttribute(window, DWMWA_TEXT_COLOR, &text_color,
                        sizeof(text_color));

  COLORREF border_color = ToColorRef(border);
  DwmSetWindowAttribute(window, DWMWA_BORDER_COLOR, &border_color,
                        sizeof(border_color));

  DWORD corners = kRoundedCorners;
  DwmSetWindowAttribute(window, DWMWA_WINDOW_CORNER_PREFERENCE, &corners,
                        sizeof(corners));
}

}  // namespace window_chrome
