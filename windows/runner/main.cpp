#include <cstdlib>
#include <string>
#include <utility>
#include <vector>

#include <windows.h>

#include <flutter/dart_project.h>

#include "runner/bootstrap/flutter_window.h"
#include "runner/data/models/window/window_geometry.h"
#include "runner/infrastructure/process/command_line.h"
#include "runner/infrastructure/process/console_support.h"
#include "runner/infrastructure/shell/application_identity.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE previous_instance, _In_ wchar_t* command_line,
                      _In_ int show_command) {
  // A second launch restores the window retained by background mode.
  const HWND existing_window = ::FindWindow(L"FLUTTER_RUNNER_WIN32_WINDOW", L"Phonolite");
  if (existing_window != nullptr) {
    ::ShowWindow(existing_window, ::IsIconic(existing_window) ? SW_RESTORE : SW_SHOW);
    ::SetForegroundWindow(existing_window);

    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    create_and_attach_console();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  if (!configure_application_identity()) {
    ::OutputDebugStringW(L"Phonolite: Windows app identity registration could not be completed.\n");
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments = get_command_line_arguments();
  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  const WindowPoint origin{10, 10};
  const WindowSize size{1280, 720};

  if (!window.create(L"Phonolite", origin, size)) {
    return EXIT_FAILURE;
  }

  window.set_quit_on_close(true);

  ::MSG message;

  while (::GetMessage(&message, nullptr, 0, 0)) {
    ::TranslateMessage(&message);
    ::DispatchMessage(&message);
  }

  ::CoUninitialize();

  return EXIT_SUCCESS;
}
