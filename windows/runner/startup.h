#ifndef RUNNER_STARTUP_H_
#define RUNNER_STARTUP_H_
#include <windows.h>
#include <string>
namespace quotamate {
// Current-user registration only. Never changes StartupApproved or machine policy.
bool StartupRegistered(const std::wstring& executable, const wchar_t* name = L"QuotaMate");
LONG RegisterStartup(bool enabled, const std::wstring& executable, const wchar_t* name = L"QuotaMate");
}
#endif
