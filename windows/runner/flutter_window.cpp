#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <memory>
#include <optional>
#include <variant>

#include "flutter/generated_plugin_registrant.h"
#include "window_chrome.h"

namespace {

// The app's own channel, not a plugin: the one thing Flutter cannot reach on
// Windows is the frame Windows draws around it. See window_chrome.h.
constexpr const char kWindowChannel[] = "mirqat/window";

// Reads an int out of the method's argument map. Flutter sends a colour as an
// int32 or an int64 depending on its size, so both are accepted; anything
// else leaves |fallback| standing.
int64_t IntArg(const flutter::EncodableMap& args,
               const char* name,
               int64_t fallback) {
  auto it = args.find(flutter::EncodableValue(name));
  if (it == args.end()) {
    return fallback;
  }
  // Not `small` and `big`: <rpcndr.h>, which arrives with <windows.h>,
  // defines `small` as `char`, so `const auto* small` compiles as
  // `const auto* char` and the error lands three lines away from the cause.
  if (const auto* narrow = std::get_if<int32_t>(&it->second)) {
    return *narrow;
  }
  if (const auto* wide = std::get_if<int64_t>(&it->second)) {
    return *wide;
  }
  return fallback;
}

bool BoolArg(const flutter::EncodableMap& args,
             const char* name,
             bool fallback) {
  auto it = args.find(flutter::EncodableValue(name));
  if (it == args.end()) {
    return fallback;
  }
  const auto* value = std::get_if<bool>(&it->second);
  return value == nullptr ? fallback : *value;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // The frame follows the theme inside it. Registered here because this is
  // where the engine and the window handle are both in hand.
  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kWindowChannel,
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "applyTheme") {
          result->NotImplemented();
          return;
        }
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        if (args == nullptr) {
          result->Error("bad_args", "applyTheme wants a map.");
          return;
        }
        window_chrome::Apply(
            GetHandle(), BoolArg(*args, "dark", false),
            static_cast<uint32_t>(IntArg(*args, "caption", 0)),
            static_cast<uint32_t>(IntArg(*args, "text", 0)),
            static_cast<uint32_t>(IntArg(*args, "border", 0)));
        result->Success();
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // Before the controller: the channel speaks to the engine's messenger, and
  // must not outlive it.
  window_channel_ = nullptr;

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
