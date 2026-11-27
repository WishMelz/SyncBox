#include "flutter_window.h"
#include "utils.h"
#include "clipboard_image.h"

#include <optional>
#include <commctrl.h>
#include <utility>
#include <shellapi.h>
#include <flutter/standard_method_codec.h>
#include <cstdint>

#include "flutter/generated_plugin_registrant.h"

namespace {
// Explorer drops onto the Flutter child HWND, which owns the client area.
LRESULT CALLBACK DropProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam,
                          UINT_PTR id, DWORD_PTR parent) {
  if (message == WM_DROPFILES) {
    return SendMessageW(reinterpret_cast<HWND>(parent), message, wparam, lparam);
  }
  if (message == WM_NCDESTROY) RemoveWindowSubclass(hwnd, DropProc, id);
  return DefSubclassProc(hwnd, message, wparam, lparam);
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
  links_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "syncbox/links",
      &flutter::StandardMethodCodec::GetInstance());
  links_channel_->SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() != "open") { result->NotImplemented(); return; }
    const auto* value = call.arguments() ? std::get_if<std::string>(call.arguments()) : nullptr;
    if (!value || value->find('\0') != std::string::npos ||
        (value->rfind("https://", 0) != 0 && value->rfind("http://", 0) != 0)) {
      result->Error("invalid", "Invalid HTTP(S) URL"); return;
    }
    const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value->data(), static_cast<int>(value->size()), nullptr, 0);
    if (size == 0) { result->Error("invalid", "Invalid URL encoding"); return; }
    std::wstring url(size, L'\0');
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value->data(), static_cast<int>(value->size()), url.data(), size);
    const auto status = reinterpret_cast<std::intptr_t>(ShellExecuteW(nullptr, L"open", url.c_str(), nullptr, nullptr, SW_SHOWNORMAL));
    if (status > 32) result->Success(flutter::EncodableValue(true));
    else result->Error("open", "Could not open URL");
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  drop_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "syncbox/file-drop",
      &flutter::StandardMethodCodec::GetInstance());
  drop_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "readClipboard") ReadClipboardImage(GetHandle(), *result);
    else result->NotImplemented();
  });
  HWND drop_view = flutter_controller_->view()->GetNativeWindow();
  if (SetWindowSubclass(drop_view, DropProc, 1, reinterpret_cast<DWORD_PTR>(GetHandle()))) {
    DragAcceptFiles(drop_view, TRUE);
  }

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
  drop_channel_.reset();
  links_channel_ = nullptr;
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
    case WM_DROPFILES: {
      auto drop = reinterpret_cast<HDROP>(wparam);
      POINT point{};
      const bool in_client = DragQueryPoint(drop, &point) != FALSE;
      flutter::EncodableList paths;
      const UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
      // Six paths suffice to report that the five-file limit was exceeded.
      for (UINT i = 0; i < count && i < 6; ++i) {
        const UINT length = DragQueryFileW(drop, i, nullptr, 0);
        std::vector<wchar_t> path(length + 1);
        if (DragQueryFileW(drop, i, path.data(), length + 1)) {
          paths.emplace_back(Utf8FromUtf16(path.data()));
        }
      }
      DragFinish(drop);
      if (drop_channel_ && in_client && !paths.empty()) {
        flutter::EncodableList args{flutter::EncodableValue(static_cast<int>(point.x)),
                                    flutter::EncodableValue(static_cast<int>(point.y)),
                                    flutter::EncodableValue(std::move(paths))};
        drop_channel_->InvokeMethod("drop", std::make_unique<flutter::EncodableValue>(std::move(args)));
      }
      return 0;
    }
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
