#ifndef PHONOLITE_RUNNER_INFRASTRUCTURE_SHELL_DIRECTORY_LAUNCHER_H_
#define PHONOLITE_RUNNER_INFRASTRUCTURE_SHELL_DIRECTORY_LAUNCHER_H_

#include <functional>
#include <string>

#include "runner/data/models/directories/directory_open_result.h"

namespace phonolite {

class DirectoryLauncher {
 public:
  using UriLauncher = std::function<DirectoryOpenResult(const std::string&)>;

  DirectoryLauncher();
  explicit DirectoryLauncher(UriLauncher launch_uri);

  DirectoryOpenResult open_directory(const std::string& absolute_path) const;

 private:
  UriLauncher launch_uri_;
};

} // namespace phonolite

#endif // PHONOLITE_RUNNER_INFRASTRUCTURE_SHELL_DIRECTORY_LAUNCHER_H_
