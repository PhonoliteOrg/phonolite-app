#include "runner/infrastructure/shell/directory_launcher.h"

#include <shellapi.h>

DirectoryLauncher::DirectoryLauncher(HWND owner_window) : owner_window_(owner_window) {}

DirectoryOpenResult DirectoryLauncher::open_directory(const std::wstring& folder_path) const {
  const auto status = reinterpret_cast<INT_PTR>(
      ShellExecuteW(owner_window_, L"open", folder_path.c_str(), nullptr, nullptr, SW_SHOWNORMAL));

  return {status};
}
