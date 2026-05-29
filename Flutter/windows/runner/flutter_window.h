#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void AddTrayIcon();
  void RemoveTrayIcon();
  void ShowTrayMenu();
  void ShowMainWindowFromTray();
  void HideToTray();
  void ShowTrayBalloon();
  void InvokeTrayAction(const std::string& action);
  void RegisterQuickAvaAiHotkey();
  void UnregisterQuickAvaAiHotkey();
  void StoreNormalWindowPlacement();
  void RestoreNormalWindowPlacement();
  void ShowAuthWindow();
  void ShowQuickAvaAiWindow();
  void HideQuickAvaAiWindow();
  void InvokeQuickAvaAi();
  void ExitFromTray();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Native window controls exposed to Flutter.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_channel_;

  bool file_drop_window_registered_ = false;
  bool file_drop_view_registered_ = false;
  HWND file_drop_view_window_ = nullptr;
  bool tray_icon_added_ = false;
  bool exit_requested_ = false;
  bool tray_balloon_shown_ = false;
  bool quick_hotkey_registered_ = false;
  bool quick_ai_window_mode_ = false;
  bool quick_ai_enabled_ = false;
  bool has_normal_window_placement_ = false;
  WINDOWPLACEMENT normal_window_placement_{};
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
