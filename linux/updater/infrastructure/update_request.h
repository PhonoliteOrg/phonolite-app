#ifndef PHONOLITE_UPDATER_INFRASTRUCTURE_UPDATE_REQUEST_H_
#define PHONOLITE_UPDATER_INFRASTRUCTURE_UPDATE_REQUEST_H_

#include <string>

#include <sys/types.h>

#include "infrastructure/system_operations.h"

namespace phonolite {
namespace updates {

struct UpdateRequest {
  pid_t process;
  std::uint64_t start;
  std::string correlation;
  std::string expected_version;

  static UpdateRequest parse(const std::string& source);
};

class PrivateUpdateRequest {
 public:
  PrivateUpdateRequest(const std::string& path, uid_t owner);
  std::string text(const char* name, std::size_t maximum) const;
  int open_file(const char* name) const;

 private:
  uid_t owner_;
  FileDescriptor directory_;
};

} // namespace updates
} // namespace phonolite
#endif
