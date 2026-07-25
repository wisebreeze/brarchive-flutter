#include "flutter_window.h"

#include <optional>
#include <shobjidl.h>
#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include "file_picker_plugin.h"
#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  RegisterFilePickerPlugin(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Enable drag-and-drop file support
  DragAcceptFiles(GetHandle(), TRUE);

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
    case WM_DROPFILES: {
      HDROP hDrop = reinterpret_cast<HDROP>(wparam);
      wchar_t filePath[MAX_PATH] = {0};
      // Get only the first dropped file
      if (DragQueryFileW(hDrop, 0, filePath, MAX_PATH)) {
        // Convert to UTF-8 and send to Flutter via method channel
        int utf8Len = WideCharToMultiByte(CP_UTF8, 0, filePath, -1,
                                          nullptr, 0, nullptr, nullptr);
        std::string utf8Path(utf8Len, 0);
        WideCharToMultiByte(CP_UTF8, 0, filePath, -1, &utf8Path[0], utf8Len,
                            nullptr, nullptr);
        // Remove trailing null
        if (!utf8Path.empty() && utf8Path.back() == '\0') {
          utf8Path.pop_back();
        }
        // Send to the share channel (reused for drag-drop on desktop)
        flutter::MethodChannel<flutter::EncodableValue>::Create(
            flutter_controller_->engine()->messenger(),
            "com.wisebreeze.brarchive/share",
            &flutter::StandardMethodCodec::GetInstance())
            ->InvokeMethod(
                "onFileDropped",
                std::make_unique<flutter::EncodableValue>(utf8Path));
      }
      DragFinish(hDrop);
      break;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
