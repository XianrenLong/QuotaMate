#ifndef RUNNER_NATIVE_BRIDGE_H_
#define RUNNER_NATIVE_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>
#include <shellapi.h>
#include <memory>
#include <string>

class NativeBridge {
 public:
  NativeBridge(HWND window, flutter::BinaryMessenger* messenger);
  ~NativeBridge();
  bool TrayAvailable() const { return tray_added_; }
  bool HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);
 private:
  void HandleCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void AddTray();
  void ApplyAppearance();
  void ShowMainWindow();
  HWND window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  NOTIFYICONDATAW tray_{};
  UINT taskbar_created_;
  bool english_ = false;
  bool tray_added_ = false;
  bool close_to_tray_ = false;
  bool quitting_ = false;
  std::string appearance_ = "light";
};
#endif
