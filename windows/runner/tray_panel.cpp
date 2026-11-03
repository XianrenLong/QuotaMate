#include "tray_panel.h"

#include <algorithm>
#include <dwmapi.h>
#include <objidl.h>
#include <shellscalingapi.h>
// GDI+ headers expect the min/max macros that NOMINMAX removes.
namespace Gdiplus { using std::min; using std::max; }
#include <gdiplus.h>
#include "resource.h"

namespace {
using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using namespace Gdiplus;
constexpr wchar_t kClass[] = L"QuotaMateTrayPanel";
constexpr wchar_t kFont[] = L"Microsoft YaHei UI";
constexpr wchar_t kIcons[] = L"Segoe MDL2 Assets";
constexpr float kWidth = 340, kPad = 16, kInner = kWidth - 2 * kPad;

std::wstring Wide(const std::string& value) {
  const int length = MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0);
  std::wstring result(length, L'\0');
  if (length) MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), result.data(), length);
  return result;
}
const EncodableValue* Find(const EncodableMap& map, const char* key) {
  const auto item = map.find(EncodableValue(key));
  return item == map.end() ? nullptr : &item->second;
}
std::string Utf8(const EncodableMap& map, const char* key) {
  const auto* value = Find(map, key);
  const auto* text = value ? std::get_if<std::string>(value) : nullptr;
  return text ? *text : "";
}
std::wstring Text(const EncodableMap& map, const char* key) { return Wide(Utf8(map, key)); }
double Number(const EncodableValue& value) {
  if (const auto* d = std::get_if<double>(&value)) return *d;
  if (const auto* i = std::get_if<int32_t>(&value)) return *i;
  if (const auto* l = std::get_if<int64_t>(&value)) return static_cast<double>(*l);
  return 0;
}
const EncodableList& List(const EncodableMap& map, const char* key) {
  static const EncodableList empty;
  const auto* value = Find(map, key);
  const auto* list = value ? std::get_if<EncodableList>(value) : nullptr;
  return list ? *list : empty;
}
const EncodableMap* Map(const EncodableValue& value) { return std::get_if<EncodableMap>(&value); }

// The app's own palette, matching lib/ui/palette.dart and the macOS panel.
struct Palette { Color card, ink, muted, tile, track, line, blue, green, amberText, amberFill, greenText; };
Color Rgb(UINT32 hex, BYTE alpha = 255) {
  return Color(alpha, static_cast<BYTE>(hex >> 16 & 0xFF), static_cast<BYTE>(hex >> 8 & 0xFF), static_cast<BYTE>(hex & 0xFF));
}
Palette Colors(bool dark) {
  return dark ? Palette{Rgb(0x252836), Rgb(0xF0F1F8), Rgb(0xABB0C4), Rgb(0x1D1F2B), Rgb(0x383D4F), Rgb(0x3A3E50),
                        Rgb(0x6BA7FF), Rgb(0x6ACF83), Rgb(0xF4CF80), Rgb(0x3E3325), Rgb(0x91DFA4)}
              : Palette{Rgb(0xFBFAFD), Rgb(0x171A29), Rgb(0x7C8099), Rgb(0xEFEEF4), Rgb(0xE5E4EE), Rgb(0xE9E8F0),
                        Rgb(0x3483FF), Rgb(0x35B54A), Rgb(0x91600A), Rgb(0xFFF4DF), Rgb(0x24833A)};
}
void Rounded(GraphicsPath& path, float x, float y, float w, float h, float r) {
  r = std::min(r, std::min(w, h) / 2);
  const float d = r * 2;
  path.AddArc(x, y, d, d, 180.0f, 90.0f);
  path.AddArc(x + w - d, y, d, d, 270.0f, 90.0f);
  path.AddArc(x + w - d, y + h - d, d, d, 0.0f, 90.0f);
  path.AddArc(x, y + h - d, d, d, 90.0f, 90.0f);
  path.CloseFigure();
}
void Fill(Graphics& g, const Color& color, float x, float y, float w, float h, float r) {
  GraphicsPath path; Rounded(path, x, y, w, h, r);
  SolidBrush brush(color); g.FillPath(&brush, &path);
}
void Stroke(Graphics& g, const Color& color, float x, float y, float w, float h, float r) {
  GraphicsPath path; Rounded(path, x, y, w, h, r);
  Pen pen(color, 1); g.DrawPath(&pen, &path);
}
// Draws one line of text in a box; returns the width the text needs.
float Draw(Graphics& g, const std::wstring& text, float size, const Color& color, float x, float y, float w, float h,
           StringAlignment align = StringAlignmentNear, bool bold = false, const wchar_t* family = kFont) {
  Font font(family, size, bold ? FontStyleBold : FontStyleRegular, UnitPixel);
  StringFormat format;
  format.SetAlignment(align);
  format.SetLineAlignment(StringAlignmentCenter);
  format.SetTrimming(StringTrimmingEllipsisCharacter);
  format.SetFormatFlags(StringFormatFlagsNoWrap);
  SolidBrush brush(color);
  g.DrawString(text.c_str(), -1, &font, RectF(x, y, w, h), &format, &brush);
  RectF box;
  g.MeasureString(text.c_str(), -1, &font, PointF(0, 0), &format, &box);
  return box.Width;
}
float Measure(Graphics& g, const std::wstring& text, float size, bool bold = false) {
  Font font(kFont, size, bold ? FontStyleBold : FontStyleRegular, UnitPixel);
  RectF box;
  g.MeasureString(text.c_str(), -1, &font, PointF(0, 0), &box);
  return box.Width;
}
}

TrayPanel::TrayPanel(Actions actions) : actions_(std::move(actions)) {
  GdiplusStartupInput input;
  GdiplusStartup(&gdiplus_, &input, nullptr);
  WNDCLASSW type{};
  type.style = CS_DROPSHADOW;
  type.lpfnWndProc = Proc;
  type.hInstance = GetModuleHandle(nullptr);
  type.hCursor = LoadCursor(nullptr, IDC_ARROW);
  type.lpszClassName = kClass;
  RegisterClassW(&type);
  hwnd_ = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_TOPMOST, kClass, L"QuotaMate", WS_POPUP,
                          0, 0, 1, 1, nullptr, nullptr, type.hInstance, this);
  // DWMWA_WINDOW_CORNER_PREFERENCE (33) = DWMWCP_ROUND (2) on Windows 11.
  const DWORD corner = 2;
  if (hwnd_) DwmSetWindowAttribute(hwnd_, 33, &corner, sizeof(corner));
}

TrayPanel::~TrayPanel() {
  if (hwnd_) DestroyWindow(hwnd_);
  UnregisterClassW(kClass, GetModuleHandle(nullptr));
  if (gdiplus_) GdiplusShutdown(gdiplus_);
}

void TrayPanel::Update(const EncodableMap& panel) {
  provider_ = Utf8(panel, "provider");
  providers_.clear();
  for (const auto& item : List(panel, "providers")) {
    if (const auto* p = Map(item)) providers_.push_back({Utf8(*p, "id"), Text(*p, "label")});
  }
  account_ = Text(panel, "account");
  status_ = Text(panel, "status");
  empty_ = Text(panel, "empty");
  today_ = Text(panel, "todayTitle");
  hours_start_ = Text(panel, "hoursStart");
  hours_label_ = Text(panel, "hoursLabel");
  hours_end_ = Text(panel, "hoursEnd");
  const auto* busy = Find(panel, "busy");
  busy_ = busy && std::get_if<bool>(busy) && *std::get_if<bool>(busy);
  windows_.clear();
  for (const auto& item : List(panel, "windows")) {
    const auto* w = Map(item);
    if (!w) continue;
    const auto* remaining = Find(*w, "remaining");
    windows_.push_back({Text(*w, "label"), Text(*w, "value"), Text(*w, "reset"), Text(*w, "forecast"),
                        Utf8(*w, "color") == "green", Utf8(*w, "forecastTone") == "warning",
                        remaining ? static_cast<int>(Number(*remaining)) : 0});
  }
  metrics_.clear();
  for (const auto& item : List(panel, "metrics")) {
    if (const auto* m = Map(item)) metrics_.push_back({Text(*m, "label"), Text(*m, "value")});
  }
  hours_.clear();
  for (const auto& item : List(panel, "hours")) hours_.push_back(std::clamp(Number(item), 0.0, 1.0));
  if (const auto* value = Find(panel, "actions")) {
    if (const auto* a = Map(*value)) {
      open_ = Text(*a, "open"); settings_ = Text(*a, "settings");
      quit_ = Text(*a, "quit"); refresh_ = Text(*a, "refresh");
    }
  }
  if (hwnd_ && IsWindowVisible(hwnd_)) Place();
}

void TrayPanel::SetDark(bool dark) {
  dark_ = dark;
  if (hwnd_) InvalidateRect(hwnd_, nullptr, FALSE);
}

void TrayPanel::Toggle(POINT anchor) {
  if (!hwnd_) return;
  if (IsWindowVisible(hwnd_)) { Hide(); return; }
  // The click that deactivated the panel arrives here right after; keep it closed.
  if (GetTickCount64() - hidden_at_ < 300) return;
  anchor_ = anchor;
  Place();
  ShowWindow(hwnd_, SW_SHOW);
  SetForegroundWindow(hwnd_);
  SetFocus(hwnd_);
}

void TrayPanel::Hide() {
  if (!hwnd_ || !IsWindowVisible(hwnd_)) return;
  ShowWindow(hwnd_, SW_HIDE);
  hidden_at_ = GetTickCount64();
}

void TrayPanel::Place() {
  const HMONITOR monitor = MonitorFromPoint(anchor_, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info{sizeof(info)};
  GetMonitorInfoW(monitor, &info);
  UINT dpi_x = 96, dpi_y = 96;
  GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &dpi_x, &dpi_y);
  scale_ = static_cast<float>(dpi_x) / 96.0f;
  Bitmap scratch(1, 1);
  Graphics measure(&scratch);
  height_ = Render(measure);
  const int width = static_cast<int>(kWidth * scale_ + 0.5f), height = static_cast<int>(height_ * scale_ + 0.5f);
  const RECT work = info.rcWork;
  const int gap = static_cast<int>(8 * scale_);
  auto clamp = [](int value, int low, int high) { return std::max(low, std::min(value, high)); };
  int x = clamp(anchor_.x - width / 2, work.left + gap, work.right - width - gap);
  int y = clamp(anchor_.y - height - gap, work.top + gap, work.bottom - height - gap);
  if (anchor_.x >= work.right) x = work.right - width - gap;
  if (anchor_.x <= work.left) x = work.left + gap;
  if (anchor_.y >= work.bottom) y = work.bottom - height - gap;
  if (anchor_.y <= work.top) y = work.top + gap;
  SetWindowPos(hwnd_, HWND_TOPMOST, x, y, width, height, SWP_NOACTIVATE);
  InvalidateRect(hwnd_, nullptr, FALSE);
}

float TrayPanel::Render(Graphics& g) {
  const Palette c = Colors(dark_);
  targets_.clear();
  float y = kPad;
  const float right = kPad + kInner;

  // Header: app name, provider switch and refresh.
  Draw(g, L"", 15, c.blue, kPad, y + 3, 20, 20, StringAlignmentNear, false, kIcons);
  Draw(g, L"QuotaMate", 15, c.ink, kPad + 24, y, 140, 26, StringAlignmentNear, true);
  const float refresh_x = right - 24;
  Draw(g, L"", 13, busy_ ? c.line : c.muted, refresh_x, y + 1, 24, 24, StringAlignmentCenter, false, kIcons);
  targets_.push_back({refresh_x, y, 24, 26, Action::kRefresh, {}});
  float pills = 4;
  std::vector<float> widths;
  for (const auto& p : providers_) {
    widths.push_back(Measure(g, p.label, 12, true) + 18);
    pills += widths.back();
  }
  float px = refresh_x - 6 - pills;
  Fill(g, c.tile, px, y + 2, pills, 22, 11);
  px += 2;
  for (size_t i = 0; i < providers_.size(); ++i) {
    const bool selected = providers_[i].id == provider_;
    if (selected) Fill(g, c.blue, px, y + 4, widths[i], 18, 9);
    Draw(g, providers_[i].label, 12, selected ? Rgb(0xFFFFFF) : c.muted, px, y + 4, widths[i], 18,
         StringAlignmentCenter, selected);
    targets_.push_back({px, y + 2, widths[i], 22, Action::kProvider, providers_[i].id});
    px += widths[i];
  }
  y += 26 + 8;

  // Account and data age.
  for (const auto* line : {&account_, &status_}) {
    if (line->empty()) continue;
    Draw(g, *line, 12, c.muted, kPad, y, kInner, 17);
    y += 17;
  }
  y += 10;

  if (windows_.empty()) {
    Fill(g, c.tile, kPad, y, kInner, 36, 7);
    Draw(g, empty_, 12, c.muted, kPad + 10, y, kInner - 20, 36);
    y += 36 + 12;
  }
  for (const auto& w : windows_) {
    Draw(g, w.label, 13, c.ink, kPad, y, kInner * 0.6f, 18);
    Draw(g, w.value, 13, c.ink, kPad, y, kInner, 18, StringAlignmentFar, true);
    y += 18 + 5;
    Fill(g, c.track, kPad, y, kInner, 7, 3.5f);
    const float share = static_cast<float>(std::clamp(w.remaining, 0, 100)) / 100.0f;
    Fill(g, w.green ? c.green : c.blue, kPad, y, std::max(4.0f, kInner * share), 7, 3.5f);
    y += 7 + 5;
    Draw(g, w.reset, 12, c.muted, kPad, y, kInner, 16);
    y += 16;
    if (!w.forecast.empty()) {
      y += 5;
      Fill(g, w.warning ? c.amberFill : c.tile, kPad, y, kInner, 26, 6);
      const Color tone = w.warning ? c.amberText : c.greenText;
      Draw(g, w.warning ? L"" : L"", 11, tone, kPad + 8, y, 16, 26, StringAlignmentNear, false, kIcons);
      Draw(g, w.forecast, 12, tone, kPad + 28, y, kInner - 36, 26);
      y += 26;
    }
    y += 12;
  }

  Pen divider(c.line, 1);
  g.DrawLine(&divider, kPad, y, right, y);
  y += 1 + 10;

  // Today.
  Draw(g, today_, 12, c.muted, kPad, y, kInner, 16);
  y += 16 + 8;
  if (!metrics_.empty()) {
    const float count = static_cast<float>(metrics_.size());
    const float tile = (kInner - 8 * (count - 1)) / count;
    for (size_t i = 0; i < metrics_.size(); ++i) {
      const float x = kPad + static_cast<float>(i) * (tile + 8);
      Fill(g, c.tile, x, y, tile, 48, 7);
      Draw(g, metrics_[i].label, 11, c.muted, x + 9, y + 6, tile - 18, 15);
      Draw(g, metrics_[i].value, 16, c.ink, x + 9, y + 21, tile - 18, 22, StringAlignmentNear, true);
    }
    y += 48 + 10;
  }
  if (!hours_.empty()) {
    const float count = static_cast<float>(hours_.size());
    const float bar = (kInner - 3 * (count - 1)) / count;
    for (size_t i = 0; i < hours_.size(); ++i) {
      const float h = std::max(2.0f, 32 * static_cast<float>(hours_[i]));
      const BYTE alpha = i + 1 == hours_.size() ? 115 : 217;
      Fill(g, Color(alpha, c.blue.GetR(), c.blue.GetG(), c.blue.GetB()), kPad + static_cast<float>(i) * (bar + 3), y + 32 - h, bar, h,
           std::min(2.0f, h / 2));
    }
    y += 32 + 4;
    Draw(g, hours_start_, 11, c.muted, kPad, y, kInner / 3, 15);
    Draw(g, hours_label_, 11, c.muted, kPad, y, kInner, 15, StringAlignmentCenter);
    Draw(g, hours_end_, 11, c.muted, kPad, y, kInner, 15, StringAlignmentFar);
    y += 15 + 12;
  }

  // Footer.
  const float open_width = Measure(g, open_, 13) + 44;
  Stroke(g, c.line, kPad, y, open_width, 30, 6);
  Draw(g, L"", 12, c.ink, kPad + 10, y, 18, 30, StringAlignmentNear, false, kIcons);
  Draw(g, open_, 13, c.ink, kPad + 32, y, open_width - 36, 30);
  targets_.push_back({kPad, y, open_width, 30, Action::kOpen, {}});
  const float quit_width = Measure(g, quit_, 13) + 4;
  Draw(g, quit_, 13, c.muted, right - quit_width, y, quit_width, 30, StringAlignmentFar);
  targets_.push_back({right - quit_width, y, quit_width, 30, Action::kQuit, {}});
  const float settings_width = Measure(g, settings_, 13) + 4;
  const float settings_x = right - quit_width - 14 - settings_width;
  Draw(g, settings_, 13, c.muted, settings_x, y, settings_width, 30, StringAlignmentFar);
  targets_.push_back({settings_x, y, settings_width, 30, Action::kSettings, {}});
  y += 30 + kPad;
  return y;
}

void TrayPanel::Paint() {
  PAINTSTRUCT paint;
  const HDC hdc = BeginPaint(hwnd_, &paint);
  RECT client; GetClientRect(hwnd_, &client);
  const HDC memory = CreateCompatibleDC(hdc);
  const HBITMAP bitmap = CreateCompatibleBitmap(hdc, client.right, client.bottom);
  const HGDIOBJ previous = SelectObject(memory, bitmap);
  {
    Graphics g(memory);
    g.SetSmoothingMode(SmoothingModeAntiAlias);
    g.SetTextRenderingHint(TextRenderingHintClearTypeGridFit);
    const Palette c = Colors(dark_);
    g.Clear(c.card);
    Pen border(c.line, 1);
    g.DrawRectangle(&border, 0, 0, static_cast<INT>(client.right - 1), static_cast<INT>(client.bottom - 1));
    g.ScaleTransform(scale_, scale_);
    Render(g);
  }
  BitBlt(hdc, 0, 0, client.right, client.bottom, memory, 0, 0, SRCCOPY);
  SelectObject(memory, previous);
  DeleteObject(bitmap);
  DeleteDC(memory);
  EndPaint(hwnd_, &paint);
}

const TrayPanel::Target* TrayPanel::Hit(LPARAM lparam) const {
  const float x = static_cast<float>(static_cast<short>(LOWORD(lparam))) / scale_;
  const float y = static_cast<float>(static_cast<short>(HIWORD(lparam))) / scale_;
  for (const auto& t : targets_) {
    if (x >= t.x && x < t.x + t.width && y >= t.y && y < t.y + t.height) return &t;
  }
  return nullptr;
}

LRESULT CALLBACK TrayPanel::Proc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_NCCREATE) {
    const auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(create->lpCreateParams));
  }
  auto* panel = reinterpret_cast<TrayPanel*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (panel && panel->hwnd_ == hwnd) return panel->Handle(message, wparam, lparam);
  return DefWindowProcW(hwnd, message, wparam, lparam);
}

LRESULT TrayPanel::Handle(UINT message, WPARAM wparam, LPARAM lparam) {
  switch (message) {
    case WM_PAINT: Paint(); return 0;
    case WM_ERASEBKGND: return 1;
    case WM_ACTIVATE:
      if (LOWORD(wparam) == WA_INACTIVE) Hide();
      return 0;
    case WM_KEYDOWN:
      if (wparam == VK_ESCAPE) Hide();
      return 0;
    case WM_DPICHANGED: Place(); return 0;
    case WM_SETCURSOR: {
      POINT point; GetCursorPos(&point); ScreenToClient(hwnd_, &point);
      if (Hit(MAKELPARAM(point.x, point.y))) { SetCursor(LoadCursor(nullptr, IDC_HAND)); return TRUE; }
      break;
    }
    case WM_LBUTTONUP: {
      const Target* target = Hit(lparam);
      if (!target) return 0;
      const Target hit = *target;
      if (hit.action == Action::kOpen || hit.action == Action::kSettings || hit.action == Action::kQuit) Hide();
      switch (hit.action) {
        case Action::kProvider: if (actions_.provider) actions_.provider(hit.provider); break;
        case Action::kRefresh: if (actions_.refresh && !busy_) actions_.refresh(); break;
        case Action::kOpen: if (actions_.open) actions_.open(); break;
        case Action::kSettings: if (actions_.settings) actions_.settings(); break;
        case Action::kQuit: if (actions_.quit) actions_.quit(); break;
      }
      return 0;
    }
  }
  return DefWindowProcW(hwnd_, message, wparam, lparam);
}
