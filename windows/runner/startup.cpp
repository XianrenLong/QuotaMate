#include "startup.h"
#include <vector>
namespace quotamate {
namespace {
constexpr const wchar_t* kRun = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
std::wstring Command(const std::wstring& executable) { return L"\"" + executable + L"\" --background"; }
}
bool StartupRegistered(const std::wstring& executable, const wchar_t* name) {
  DWORD bytes = 0;
  if (RegGetValueW(HKEY_CURRENT_USER, kRun, name, RRF_RT_REG_SZ, nullptr, nullptr, &bytes) != ERROR_SUCCESS || bytes > 65536) return false;
  std::vector<wchar_t> value(bytes / sizeof(wchar_t) + 1, L'\0');
  if (RegGetValueW(HKEY_CURRENT_USER, kRun, name, RRF_RT_REG_SZ, nullptr, value.data(), &bytes) != ERROR_SUCCESS) return false;
  return _wcsicmp(value.data(), Command(executable).c_str()) == 0;
}
LONG RegisterStartup(bool enabled, const std::wstring& executable, const wchar_t* name) {
  const auto command = Command(executable);
  if (enabled && (executable.empty() || executable.find(L'"') != std::wstring::npos || command.size() >= 260)) return ERROR_INVALID_PARAMETER;
  HKEY key = nullptr;
  LONG status = RegCreateKeyExW(HKEY_CURRENT_USER, kRun, 0, nullptr, 0, KEY_SET_VALUE, nullptr, &key, nullptr);
  if (status != ERROR_SUCCESS) return status;
  if (enabled) status = RegSetValueExW(key, name, 0, REG_SZ, reinterpret_cast<const BYTE*>(command.c_str()), static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
  else { status = RegDeleteValueW(key, name); if (status == ERROR_FILE_NOT_FOUND) status = ERROR_SUCCESS; }
  RegCloseKey(key);
  return status;
}
}
