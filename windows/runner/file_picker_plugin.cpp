#include "file_picker_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/standard_message_codec.h>
#include <shobjidl.h>
#include <windows.h>

#include <codecvt>
#include <locale>
#include <memory>
#include <string>
#include <vector>

namespace {

std::string WstringToUtf8(const std::wstring& wstr) {
  if (wstr.empty()) return "";
  int size = WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(),
                                 static_cast<int>(wstr.size()), nullptr, 0,
                                 nullptr, nullptr);
  std::string result(size, 0);
  WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(),
                      static_cast<int>(wstr.size()), &result[0], size,
                      nullptr, nullptr);
  return result;
}

std::wstring Utf8ToWstring(const std::string& str) {
  if (str.empty()) return L"";
  int size = MultiByteToWideChar(CP_UTF8, 0, str.c_str(),
                                 static_cast<int>(str.size()), nullptr, 0);
  std::wstring result(size, 0);
  MultiByteToWideChar(CP_UTF8, 0, str.c_str(), static_cast<int>(str.size()),
                      &result[0], size);
  return result;
}

// Opens a file picker dialog. Returns the selected file path or empty string.
std::wstring PickFile(HWND parent, const std::vector<std::string>& extensions) {
  std::wstring filter = L"All files (*.*)\0*.*\0";
  if (!extensions.empty()) {
    std::wstring ext_list;
    std::wstring desc = L"Supported files (";
    for (size_t i = 0; i < extensions.size(); ++i) {
      if (i > 0) {
        desc += L"; ";
        ext_list += L";";
      }
      desc += L"*." + Utf8ToWstring(extensions[i]);
      ext_list += L"*." + Utf8ToWstring(extensions[i]);
    }
    desc += L")";
    filter = desc + L'\0' + ext_list + L'\0' + L"All files (*.*)\0*.*\0";
  }

  wchar_t file_path[MAX_PATH] = {0};
  OPENFILENAMEW ofn = {0};
  ofn.lStructSize = sizeof(ofn);
  ofn.hwndOwner = parent;
  ofn.lpstrFile = file_path;
  ofn.nMaxFile = MAX_PATH;
  ofn.lpstrFilter = filter.c_str();
  ofn.nFilterIndex = 1;
  ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR;

  if (GetOpenFileNameW(&ofn)) {
    return file_path;
  }
  return L"";
}

// Opens a folder picker dialog. Returns the selected folder path or empty.
std::wstring PickFolder(HWND parent) {
  std::wstring result;
  IFileDialog* pfd = nullptr;
  HRESULT hr = CoCreateInstance(CLSID_FileOpenDialog, NULL, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&pfd));
  if (SUCCEEDED(hr)) {
    DWORD options;
    pfd->GetOptions(&options);
    pfd->SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM);
    if (SUCCEEDED(pfd->Show(parent))) {
      IShellItem* psi = nullptr;
      if (SUCCEEDED(pfd->GetResult(&psi))) {
        PWSTR path = nullptr;
        if (SUCCEEDED(psi->GetDisplayName(SIGDN_FILESYSPATH, &path))) {
          result = path;
          CoTaskMemFree(path);
        }
        psi->Release();
      }
    }
    pfd->Release();
  }
  return result;
}

class FilePickerPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrar* registrar) {
    auto channel =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(), "com.wisebreeze.brarchive/file_picker",
            &flutter::StandardMethodCodec::GetInstance());

    auto plugin = std::make_unique<FilePickerPlugin>(registrar);
    channel->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto& call, auto result) {
          plugin_pointer->HandleMethodCall(call, std::move(result));
        });
    registrar->AddPlugin(std::move(plugin));
  }

  explicit FilePickerPlugin(flutter::PluginRegistrar* registrar)
      : registrar_(registrar) {}

  ~FilePickerPlugin() override = default;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    if (call.method_name() == "pickFile") {
      std::vector<std::string> extensions;
      auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
      if (args != nullptr) {
        auto it = args->find(flutter::EncodableValue("extensions"));
        if (it != args->end()) {
          auto* ext_list = std::get_if<flutter::EncodableList>(&it->second);
          if (ext_list != nullptr) {
            for (const auto& e : *ext_list) {
              if (std::holds_alternative<std::string>(e)) {
                extensions.push_back(std::get<std::string>(e));
              }
            }
          }
        }
      }
      HWND hwnd = GetRootWindow();
      std::wstring path = PickFile(hwnd, extensions);
      if (path.empty()) {
        result->Success(flutter::EncodableValue(""));
      } else {
        result->Success(flutter::EncodableValue(WstringToUtf8(path)));
      }
    } else if (call.method_name() == "pickDirectory") {
      HWND hwnd = GetRootWindow();
      std::wstring path = PickFolder(hwnd);
      if (path.empty()) {
        result->Success(flutter::EncodableValue(""));
      } else {
        result->Success(flutter::EncodableValue(WstringToUtf8(path)));
      }
    } else if (call.method_name() == "resolvePath") {
      // On Windows, paths are already filesystem paths; just return as-is.
      auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
      if (args != nullptr) {
        auto it = args->find(flutter::EncodableValue("uri"));
        if (it != args->end() && std::holds_alternative<std::string>(it->second)) {
          result->Success(flutter::EncodableValue(std::get<std::string>(it->second)));
          return;
        }
      }
      result->Success(flutter::EncodableValue(""));
    } else {
      result->NotImplemented();
    }
  }

  HWND GetRootWindow() {
    return reinterpret_cast<HWND>(registrar_->view()->GetNativeWindow());
  }

  flutter::PluginRegistrar* registrar_;
};

}  // namespace

void FilePickerPluginRegisterWithEngine(flutter::FlutterEngine* engine) {
  FilePickerPlugin::RegisterWithRegistrar(engine->GetRegistrarForPlugin("FilePickerPlugin"));
}
