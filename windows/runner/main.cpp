#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <algorithm>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // One process per Windows session protects restore and local database work.
  HANDLE instance_mutex = ::CreateMutexW(nullptr, FALSE,
      L"Local\\ToePwarPOS_461440e6_04b8_4451_8e49_8a4583db6986");
  if (instance_mutex == nullptr) {
    ::MessageBoxW(nullptr, L"Could not start safely. Close TP POS and retry.",
                  L"Toe Pwar POS", MB_OK | MB_ICONERROR);
    return EXIT_FAILURE;
  }
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing = ::FindWindowW(nullptr, L"Toe Pwar POS");
    if (existing != nullptr) {
      if (::IsIconic(existing)) ::ShowWindow(existing, SW_RESTORE);
      ::SetForegroundWindow(existing);
    }
    ::CloseHandle(instance_mutex);
    return EXIT_SUCCESS;
  }
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  RECT work_area{};
  ::SystemParametersInfoW(SPI_GETWORKAREA, 0, &work_area, 0);
  const UINT dpi = ::GetDpiForSystem();
  const double scale = (dpi == 0 ? 96 : dpi) / 96.0;
  const unsigned int available_width = static_cast<unsigned int>(
      std::max(320.0, (work_area.right - work_area.left) / scale - 32));
  const unsigned int available_height = static_cast<unsigned int>(
      std::max(320.0, (work_area.bottom - work_area.top) / scale - 32));
  Win32Window::Size size(std::min(1100u, available_width),
                         std::min(650u, available_height));
  if (!window.Create(L"Toe Pwar POS", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  ::CloseHandle(instance_mutex);
  return EXIT_SUCCESS;
}
