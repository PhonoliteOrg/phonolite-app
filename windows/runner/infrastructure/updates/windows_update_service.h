#ifndef RUNNER_INFRASTRUCTURE_UPDATES_WINDOWS_UPDATE_SERVICE_H_
#define RUNNER_INFRASTRUCTURE_UPDATES_WINDOWS_UPDATE_SERVICE_H_

#include <windows.h>

#include "runner/infrastructure/updates/update_service.h"

class WindowsUpdateService final : public UpdateService {
 public:
  WindowsUpdateService() = default;
  ~WindowsUpdateService() override;

  WindowsUpdateService(const WindowsUpdateService&) = delete;
  WindowsUpdateService& operator=(const WindowsUpdateService&) = delete;

  bool initialize() override;
  std::string feed_url() const override;
  std::string current_version() const override;
  std::string public_key() const override;
  unsigned long stage_update(const std::wstring& path, const std::string& version) override;
  unsigned long install_update() override;
  void release_update() override;
  void cleanup() override;

 private:
  std::wstring install_directory_;
  std::wstring candidate_path_;
  HANDLE candidate_file_ = INVALID_HANDLE_VALUE;
  bool initialized_ = false;
};

#endif // RUNNER_INFRASTRUCTURE_UPDATES_WINDOWS_UPDATE_SERVICE_H_
