// Temporary current-user value only; never modifies the real QuotaMate entry.
#include <windows.h>
#include <iostream>
#include "../windows/runner/startup.h"
int wmain() {
  const auto name = L"QuotaMateCiTest-" + std::to_wstring(GetCurrentProcessId());
  const std::wstring executable = L"C:\\Synthetic 额度\\QuotaMate.exe";
  struct Cleanup {
    std::wstring executable, name;
    ~Cleanup() { quotamate::RegisterStartup(false, executable, name.c_str()); }
  } cleanup{executable, name};
  if (quotamate::StartupRegistered(executable, name.c_str())) return 1;
  if (quotamate::RegisterStartup(true, executable, name.c_str()) != ERROR_SUCCESS) return 2;
  if (!quotamate::StartupRegistered(executable, name.c_str())) return 3;
  if (quotamate::StartupRegistered(L"C:\\Other\\QuotaMate.exe", name.c_str())) return 4;
  if (quotamate::RegisterStartup(true, std::wstring(300, L'x'), name.c_str()) != ERROR_INVALID_PARAMETER) return 5;
  if (!quotamate::StartupRegistered(executable, name.c_str())) return 6;
  if (quotamate::RegisterStartup(false, executable, name.c_str()) != ERROR_SUCCESS) return 7;
  if (quotamate::StartupRegistered(executable, name.c_str())) return 8;
  std::cout << "Current-user startup registration, path binding and cleanup passed.\n";
  return 0;
}
