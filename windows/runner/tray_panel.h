#ifndef RUNNER_TRAY_PANEL_H_
#define RUNNER_TRAY_PANEL_H_

#include <flutter/encodable_value.h>
#include <windows.h>
#include <functional>
#include <string>
#include <vector>

namespace Gdiplus { class Graphics; }

// The tray popup. Dart sends every string and number already localized, so
// this class only lays them out and reports clicks back.
class TrayPanel {
 public:
  struct Actions {
    std::function<void(const std::string&)> provider;
    std::function<void()> refresh, open, settings, quit;
  };
  explicit TrayPanel(Actions actions);
  ~TrayPanel();
  void Update(const flutter::EncodableMap& panel);
  void SetDark(bool dark);
  // Opens next to a tray anchor in physical pixels, or closes when open.
  void Toggle(POINT anchor);
  void Hide();

 private:
  struct Window {
    std::wstring label, unit, value, reset, forecast;
    bool green = false, warning = false;
    int remaining = 0;
  };
  struct Metric { std::wstring label, value; };
  struct Provider { std::string id; std::wstring label; };
  enum class Action { kProvider, kRefresh, kOpen, kSettings, kQuit };
  struct Target { float x, y, width, height; Action action; std::string provider; };
  static LRESULT CALLBACK Proc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
  LRESULT Handle(UINT message, WPARAM wparam, LPARAM lparam);
  float Render(Gdiplus::Graphics& g);
  void Place();
  void Paint();
  const Target* Hit(LPARAM lparam) const;

  Actions actions_;
  HWND hwnd_ = nullptr;
  ULONG_PTR gdiplus_ = 0;
  bool dark_ = false, online_ = true, busy_ = false;
  float scale_ = 1, height_ = 480;
  POINT anchor_{};
  ULONGLONG hidden_at_ = 0;
  std::string provider_ = "gpt";
  std::vector<Provider> providers_;
  std::wstring account_, status_, empty_, today_, hours_start_, hours_label_, hours_end_;
  std::wstring open_ = L"Open QuotaMate", settings_ = L"Settings", quit_ = L"Quit", refresh_ = L"Refresh";
  std::vector<Window> windows_;
  std::vector<Metric> metrics_;
  std::vector<double> hours_;
  std::vector<Target> targets_;
};
#endif
