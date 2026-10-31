#ifndef PHONOLITE_UPDATER_INFRASTRUCTURE_PACKAGE_MANAGER_H_
#define PHONOLITE_UPDATER_INFRASTRUCTURE_PACKAGE_MANAGER_H_

#include <functional>
#include <string>
#include <vector>

#include "data/models/update_types.h"

namespace phonolite {
namespace updates {

class PackageManager {
 public:
  using Runner = std::function<CommandResult(const std::vector<std::string>&, unsigned)>;

  explicit PackageManager(std::string format, Runner runner);
  void verify_installed(const Installation& installation, const std::string& executable) const;
  void verify_candidate(const Asset& asset, const std::string& path) const;
  void preflight(const std::string& path) const;
  void install(const std::string& path) const;
  std::vector<std::string> install_arguments(const std::string& path) const;

 private:
  std::string command(const std::vector<std::string>& arguments, unsigned timeout = 60) const;
  std::string format_;
  Runner runner_;
};

} // namespace updates
} // namespace phonolite

#endif
