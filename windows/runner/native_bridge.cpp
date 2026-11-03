#include "native_bridge.h"

#include <flutter/standard_method_codec.h>
#include <dwmapi.h>
#include <shobjidl.h>
#include <wrl/client.h>
#include <algorithm>
#include <filesystem>
#include <fstream>
#include <vector>
#include "resource.h"
#include "utils.h"

namespace {
using flutter::EncodableValue;
using flutter::EncodableMap;
using Microsoft::WRL::ComPtr;
constexpr UINT kTrayMessage = WM_APP + 42;
constexpr UINT kOpen = 1001, kRefresh = 1002, kQuit = 1003;
std::wstring Wide(const std::string& value) {
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
      value.data(), static_cast<int>(value.size()), nullptr, 0);
  std::wstring result(length, L'\0');
  if (length) MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), result.data(), length);
  return result;
}
std::string Argument(const EncodableMap* args, const char* key) {
  if (!args) return {};
  const auto item = args->find(EncodableValue(key));
  if (item == args->end()) return {};
  const auto* text = std::get_if<std::string>(&item->second);
  return text ? *text : "";
}
std::wstring ModuleDirectory() {
  std::vector<wchar_t> buffer(32768);
  const DWORD length = GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
  return std::filesystem::path(std::wstring(buffer.data(), length)).parent_path().wstring();
}
bool Open(HWND hwnd, const std::wstring& target, const wchar_t* arguments = nullptr) {
  return reinterpret_cast<INT_PTR>(ShellExecuteW(hwnd, L"open", target.c_str(), arguments, nullptr, SW_SHOWNORMAL)) > 32;
}
std::wstring PowerShell() {
  wchar_t system[MAX_PATH];
  const UINT length = GetSystemDirectoryW(system, MAX_PATH);
  return std::wstring(system, length) + L"\\WindowsPowerShell\\v1.0\\powershell.exe";
}
}

NativeBridge::NativeBridge(HWND window, flutter::BinaryMessenger* messenger)
    : window_(window), taskbar_created_(RegisterWindowMessageW(L"TaskbarCreated")) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "dev.quotamate/native", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleCall(call, std::move(result));
  });
  tray_.cbSize = sizeof(tray_);
  tray_.hWnd = window_;
  tray_.uID = 1;
  tray_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  tray_.uCallbackMessage = kTrayMessage;
  tray_.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(tray_.szTip, L"QuotaMate");
  AddTray();
  ApplyAppearance();
}
NativeBridge::~NativeBridge() {
  channel_->SetMethodCallHandler(nullptr);
  if (tray_added_) Shell_NotifyIconW(NIM_DELETE, &tray_);
}
void NativeBridge::AddTray() {
  tray_added_ = Shell_NotifyIconW(NIM_ADD, &tray_) != FALSE;
  if (tray_added_) {
    tray_.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &tray_);
  }
}
void NativeBridge::ShowMainWindow() {
  ShowWindow(window_, IsIconic(window_) ? SW_RESTORE : SW_SHOW);
  SetForegroundWindow(window_);
}
void NativeBridge::ApplyAppearance() {
  BOOL dark = appearance_ == "dark";
  if (appearance_ == "system") {
    DWORD light = 1, bytes = sizeof(light);
    RegGetValueW(HKEY_CURRENT_USER,
        L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
        L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &light, &bytes);
    dark = light == 0;
  }
  // DWMWA_USE_IMMERSIVE_DARK_MODE (20), supported on current Windows 10/11.
  DwmSetWindowAttribute(window_, 20, &dark, sizeof(dark));
}
bool NativeBridge::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  (void)wparam;
  if (message == taskbar_created_) { AddTray(); return true; }
  if (message == WM_SETTINGCHANGE) { ApplyAppearance(); return false; }
  if (message != kTrayMessage) return false;
  const UINT event = LOWORD(lparam);
  if (event == NIN_SELECT || event == NIN_KEYSELECT || event == WM_LBUTTONDBLCLK) {
    ShowMainWindow();
  } else if (event == WM_CONTEXTMENU || event == WM_RBUTTONUP) {
    const HMENU menu = CreatePopupMenu();
    AppendMenuW(menu, MF_STRING, kOpen, english_ ? L"Open QuotaMate" : L"打开 QuotaMate");
    AppendMenuW(menu, MF_STRING, kRefresh, english_ ? L"Refresh limits" : L"刷新额度");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, kQuit, english_ ? L"Quit QuotaMate" : L"退出 QuotaMate");
    POINT position; GetCursorPos(&position);
    SetForegroundWindow(window_);
    const UINT action = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON,
        position.x, position.y, 0, window_, nullptr);
    DestroyMenu(menu);
    PostMessageW(window_, WM_NULL, 0, 0);
    if (action == kOpen) ShowMainWindow();
    if (action == kRefresh) channel_->InvokeMethod("refresh", nullptr);
    if (action == kQuit) PostMessageW(window_, WM_CLOSE, 0, 0);
  }
  return true;
}

void NativeBridge::HandleCall(const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const auto* args = std::get_if<EncodableMap>(call.arguments());
  const auto& method = call.method_name();
  if (method == "setLanguage") {
    english_ = Argument(args, "language") == "en";
  } else if (method == "setAppearance") {
    appearance_ = Argument(args, "appearance"); ApplyAppearance();
  } else if (method == "dragWindow") {
    ReleaseCapture(); SendMessageW(window_, WM_NCLBUTTONDOWN, HTCAPTION, 0);
  } else if (method == "chooseDirectory" || method == "chooseExecutable" || method == "saveCsv") {
    ComPtr<IFileDialog> dialog;
    const bool save = method == "saveCsv";
    HRESULT status = CoCreateInstance(save ? CLSID_FileSaveDialog : CLSID_FileOpenDialog,
        nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog));
    if (FAILED(status)) { result->Error("dialog", "Unable to open file dialog"); return; }
    DWORD options = 0; dialog->GetOptions(&options);
    options |= FOS_FORCEFILESYSTEM | FOS_NOCHANGEDIR;
    if (method == "chooseDirectory") options |= FOS_PICKFOLDERS | FOS_PATHMUSTEXIST;
    if (method == "chooseExecutable") options |= FOS_FILEMUSTEXIST;
    if (save) options |= FOS_OVERWRITEPROMPT;
    dialog->SetOptions(options);
    dialog->SetTitle(english_ ? (save ? L"Export usage" : L"Choose a local data folder or executable")
                              : (save ? L"导出用量" : L"选择本机数据目录或可执行文件"));
    const COMDLG_FILTERSPEC csv[] = {{L"CSV", L"*.csv"}};
    const COMDLG_FILTERSPEC exe[] = {{L"Executable", L"*.exe"}};
    if (save) {
      dialog->SetFileTypes(1, csv); dialog->SetDefaultExtension(L"csv");
      dialog->SetFileName(Wide(Argument(args, "name")).c_str());
    } else if (method == "chooseExecutable") dialog->SetFileTypes(1, exe);
    status = dialog->Show(window_);
    if (status == HRESULT_FROM_WIN32(ERROR_CANCELLED)) { result->Success(); return; }
    ComPtr<IShellItem> item;
    PWSTR filename = nullptr;
    if (FAILED(status) || FAILED(dialog->GetResult(&item)) ||
        FAILED(item->GetDisplayName(SIGDN_FILESYSPATH, &filename))) {
      result->Error("dialog", "Unable to read selected path"); return;
    }
    const std::wstring selected(filename); CoTaskMemFree(filename);
    if (save) {
      std::ofstream file(std::filesystem::path(selected), std::ios::binary | std::ios::trunc);
      file << Argument(args, "content"); file.close();
      if (file.fail()) { result->Error("save", "Unable to save usage file"); return; }
    }
    result->Success(EncodableValue(Utf8FromUtf16(selected.c_str()))); return;
  } else if (method == "reveal") {
    const auto path = Wide(Argument(args, "path"));
    PIDLIST_ABSOLUTE item = ILCreateFromPathW(path.c_str());
    if (item) { SHOpenFolderAndSelectItems(item, 0, nullptr, 0); ILFree(item); }
  } else if (method == "openUrl") {
    const auto url = Argument(args, "url");
    if (url.rfind("https://", 0) == 0) Open(window_, Wide(url));
  } else if (method == "openClaude" || method == "openCodex") {
    const wchar_t* name = method == "openClaude" ? L"Claude.exe" : L"Codex.exe";
    // ShellExecute uses registered App Paths / app execution aliases. Never invoke a shell command.
    result->Success(EncodableValue(Open(window_, name))); return;
  } else if (method == "claudeHelperPath") {
    const auto path = ModuleDirectory() + L"\\quotamate-claude-statusline.exe";
    if (GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES)
      result->Success(EncodableValue(Utf8FromUtf16(path.c_str())));
    else result->Success();
    return;
  } else if (method == "launchClaudeLogin") {
    const std::filesystem::path path(Wide(Argument(args, "path")));
    if (path.extension() != L".ps1" || !std::filesystem::is_regular_file(path) ||
        path.wstring().find(L'"') != std::wstring::npos) {
      result->Success(EncodableValue(false)); return;
    }
    const auto encoded = Argument(args, "encoded");
    if (encoded.empty() || encoded.find_first_not_of("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=") != std::string::npos) {
      result->Success(EncodableValue(false)); return;
    }
    // An inline official login command does not change the user's execution policy.
    const auto params = L"-NoLogo -NoProfile -NoExit -EncodedCommand " + Wide(encoded);
    result->Success(EncodableValue(Open(window_, PowerShell(), params.c_str()))); return;
  } else if (method == "updateTray") {
    const auto tooltip = Wide("QuotaMate · " + Argument(args, "title") + "\n" + Argument(args, "tooltip"));
    wcsncpy_s(tray_.szTip, tooltip.c_str(), _TRUNCATE);
    tray_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
    Shell_NotifyIconW(NIM_MODIFY, &tray_);
  } else if (method == "requestNotifications") {
    result->Success(EncodableValue(tray_added_)); return;
  } else if (method == "notify") {
    wcsncpy_s(tray_.szInfoTitle, Wide(Argument(args, "title")).c_str(), _TRUNCATE);
    wcsncpy_s(tray_.szInfo, Wide(Argument(args, "body")).c_str(), _TRUNCATE);
    tray_.dwInfoFlags = NIIF_INFO;
    tray_.uFlags = NIF_INFO;
    Shell_NotifyIconW(NIM_MODIFY, &tray_);
    tray_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  } else { result->NotImplemented(); return; }
  result->Success();
}
