#include "file_picker_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <shobjidl.h>
#include <windows.h>

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

// Opens a file picker dialog using the classic GetOpenFileNameW API.
// Returns the selected file path or empty string if cancelled.
std::wstring PickFile(const std::vector<std::string>& extensions) {
  const int kMaxPath = 32768;
  std::vector<wchar_t> file_buf(kMaxPath, L'\0');

  // Build filter string: "Supported files (*.zip;*.mcpack)\0*.zip;*.mcpack\0"
  // followed by "All files (*.*)\0*.*\0\0"
  std::wstring filter;
  if (!extensions.empty()) {
    std::wstring desc = L"Supported files (";
    std::wstring ext_list;
    for (size_t i = 0; i < extensions.size(); ++i) {
      std::wstring ext = Utf8ToWstring(extensions[i]);
      if (i > 0) {
        desc += L";";
        ext_list += L";";
      }
      desc += L"*." + ext;
      ext_list += L"*." + ext;
    }
    desc += L")";
    filter = desc + L'\0' + ext_list + L'\0';
  }
  filter += L"All files (*.*)\0*.*\0";
  filter += L'\0';  // double null terminator

  OPENFILENAMEW ofn = {0};
  ofn.lStructSize = sizeof(ofn);
  ofn.hwndOwner = GetForegroundWindow();
  ofn.lpstrFile = file_buf.data();
  ofn.nMaxFile = kMaxPath;
  ofn.lpstrFilter = filter.c_str();
  ofn.nFilterIndex = 1;
  ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR;

  if (GetOpenFileNameW(&ofn)) {
    return std::wstring(file_buf.data());
  }
  return L"";
}

// Opens a folder picker dialog using the modern IFileDialog API (Vista+).
// Returns the selected folder path or empty string if cancelled.
std::wstring PickFolder() {
  std::wstring result;

  IFileDialog* dialog = nullptr;
  HRESULT hr = CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_ALL,
                                IID_PPV_ARGS(&dialog));
  if (FAILED(hr)) return result;

  // Set the dialog to pick folders instead of files.
  DWORD options;
  dialog->GetOptions(&options);
  dialog->SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM);

  hr = dialog->Show(GetForegroundWindow());
  if (SUCCEEDED(hr)) {
    IShellItem* item = nullptr;
    hr = dialog->GetResult(&item);
    if (SUCCEEDED(hr)) {
      PWSTR path = nullptr;
      hr = item->GetDisplayName(SIGDN_FILESYSPATH, &path);
      if (SUCCEEDED(hr) && path) {
        result = std::wstring(path);
        CoTaskMemFree(path);
      }
      item->Release();
    }
  }
  dialog->Release();
  return result;
}

class FilePickerPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
    auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        registrar->messenger(), "com.wisebreeze.brarchive/file_picker",
        &flutter::StandardMethodCodec::GetInstance());

    auto plugin = std::make_unique<FilePickerPlugin>();
    channel->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto& call, auto result) {
          plugin_pointer->HandleMethodCall(call, std::move(result));
        });
    registrar->AddPlugin(std::move(plugin));
  }

  FilePickerPlugin() = default;
  ~FilePickerPlugin() override = default;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    if (call.method_name() == "pickFile") {
      std::vector<std::string> extensions;
      const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
      if (args != nullptr) {
        auto it = args->find(flutter::EncodableValue("extensions"));
        if (it != args->end() &&
            std::holds_alternative<flutter::EncodableList>(it->second)) {
          for (const auto& ext : std::get<flutter::EncodableList>(it->second)) {
            if (std::holds_alternative<std::string>(ext)) {
              extensions.push_back(std::get<std::string>(ext));
            }
          }
        }
      }
      std::wstring path = PickFile(extensions);
      result->Success(flutter::EncodableValue(WstringToUtf8(path)));
    } else if (call.method_name() == "pickDirectory") {
      std::wstring path = PickFolder();
      result->Success(flutter::EncodableValue(WstringToUtf8(path)));
    } else if (call.method_name() == "resolvePath") {
      // On Windows, paths are already filesystem paths; return as-is.
      const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
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
};

}  // namespace

void RegisterFilePickerPlugin(flutter::FlutterEngine* engine) {
  auto* registrar = flutter::PluginRegistrarManager::GetInstance()
                        ->GetRegistrar<flutter::PluginRegistrarWindows>(
                            engine->GetRegistrarForPlugin("FilePickerPlugin"));
  FilePickerPlugin::RegisterWithRegistrar(registrar);
}
