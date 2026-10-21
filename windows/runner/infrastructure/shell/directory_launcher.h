#ifndef RUNNER_INFRASTRUCTURE_SHELL_DIRECTORY_LAUNCHER_H_
#define RUNNER_INFRASTRUCTURE_SHELL_DIRECTORY_LAUNCHER_H_

#include <string>

#include <windows.h>

#include "runner/data/models/directories/directory_open_result.h"

class DirectoryLauncher final {
 public:
  explicit DirectoryLauncher(HWND owner_window);

  DirectoryOpenResult open_directory(const std::wstring& folder_path) const;

 private:
  HWND owner_window_; // Borrowed; the owning window outlives this launcher.
};

#endif // RUNNER_INFRASTRUCTURE_SHELL_DIRECTORY_LAUNCHER_H_
