#ifndef RUNNER_BOOTSTRAP_FLUTTER_WINDOW_H_
#define RUNNER_BOOTSTRAP_FLUTTER_WINDOW_H_

#include <memory>

#include <flutter/dart_project.h>

#include "runner/ui/shell/win32_window.h"

namespace flutter {
class FlutterViewController;
}

class DirectoriesChannelAdapter;
class DirectoryLauncher;

class FlutterWindow final : public Win32Window {
 public:
  explicit FlutterWindow(const flutter::DartProject& project);
  ~FlutterWindow() override;

  FlutterWindow(const FlutterWindow&) = delete;
  FlutterWindow& operator=(const FlutterWindow&) = delete;

 protected:
  bool on_create() override;
  void on_destroy() override;
  LRESULT message_handler(HWND window, UINT message, WPARAM wparam, LPARAM lparam) noexcept override;

 private:
  flutter::DartProject project_;
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<DirectoryLauncher> directory_launcher_;
  std::unique_ptr<DirectoriesChannelAdapter> directory_channel_;
};

#endif // RUNNER_BOOTSTRAP_FLUTTER_WINDOW_H_
