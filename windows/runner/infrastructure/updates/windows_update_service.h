#ifndef RUNNER_INFRASTRUCTURE_UPDATES_WINDOWS_UPDATE_SERVICE_H_
#define RUNNER_INFRASTRUCTURE_UPDATES_WINDOWS_UPDATE_SERVICE_H_

#include <windows.h>

#include "runner/infrastructure/updates/update_service.h"

class WindowsUpdateService final : public UpdateService {
 public:
  explicit WindowsUpdateService(HWND owner_window);
  ~WindowsUpdateService() override;

  WindowsUpdateService(const WindowsUpdateService&) = delete;
  WindowsUpdateService& operator=(const WindowsUpdateService&) = delete;

  bool initialize() override;
  std::string feed_url() const override;
  std::string current_version() const override;
  bool is_shutdown_message(UINT message) const;
  void show_update() override;
  void cleanup() override;

 private:
  HWND owner_window_; // Borrowed; teardown stops callbacks before the window is destroyed.
  bool initialized_ = false;
};

#endif // RUNNER_INFRASTRUCTURE_UPDATES_WINDOWS_UPDATE_SERVICE_H_
