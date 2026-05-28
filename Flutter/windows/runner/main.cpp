#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shobjidl.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kAvaSingleInstanceMutexName[] =
    L"Local\\ABBA-S.AVA.SingleInstance";
constexpr wchar_t kAvaShowMainWindowMessageName[] =
    L"ABBA-S.AVA.ShowMainWindow";

UINT AvaShowMainWindowMessage() {
  static UINT message = ::RegisterWindowMessageW(kAvaShowMainWindowMessageName);
  return message;
}

void NotifyExistingAvaInstance() {
  const UINT message = AvaShowMainWindowMessage();
  if (message == 0) {
    return;
  }
  ::AllowSetForegroundWindow(ASFW_ANY);
  for (int attempt = 0; attempt < 8; ++attempt) {
    ::PostMessageW(HWND_BROADCAST, message, 0, 0);
    ::Sleep(80);
  }
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  ::SetCurrentProcessExplicitAppUserModelID(L"ABBA-S.AVA");

  HANDLE single_instance_mutex =
      ::CreateMutexW(nullptr, TRUE, kAvaSingleInstanceMutexName);
  if (single_instance_mutex &&
      ::GetLastError() == ERROR_ALREADY_EXISTS) {
    NotifyExistingAvaInstance();
    ::CloseHandle(single_instance_mutex);
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(460, 720);
  if (!window.Create(L"AVA", origin, size)) {
    if (single_instance_mutex) {
      ::ReleaseMutex(single_instance_mutex);
      ::CloseHandle(single_instance_mutex);
    }
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (single_instance_mutex) {
    ::ReleaseMutex(single_instance_mutex);
    ::CloseHandle(single_instance_mutex);
  }
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
