#include "infrastructure/update_request.h"

#include <regex>
#include <stdexcept>

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include "data/models/update_types.h"
#include "infrastructure/update_json.h"

namespace phonolite {
namespace updates {

UpdateRequest UpdateRequest::parse(const std::string& source) {
  JsonDocument request(source);
  const auto process = integer_value(request.object(), "pid");
  const auto start = integer_value(request.object(), "start");
  const auto correlation = string_value(request.object(), "correlation");
  const auto version = string_value(request.object(), "expected_version");
  if (integer_value(request.object(), "schema") != 1 || process <= 1 || static_cast<pid_t>(process) != process ||
      start == 0 || !std::regex_match(correlation, std::regex("[a-f0-9]{32}"))) {
    throw std::runtime_error("Invalid update request protocol.");
  }
  Version::parse(version);
  return {static_cast<pid_t>(process), static_cast<std::uint64_t>(start), correlation, version};
}

PrivateUpdateRequest::PrivateUpdateRequest(const std::string& path, uid_t owner)
    : owner_(owner), directory_(open(path.c_str(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)) {
  struct stat info{};
  if (path.empty() || path.front() != '/' || fstat(directory_.get(), &info) != 0 || info.st_uid != owner ||
      (info.st_mode & 077) != 0) {
    throw std::runtime_error("Update staging must be a private directory owned by the desktop user.");
  }
}

int PrivateUpdateRequest::open_file(const char* name) const {
  // This capability accepts only protocol filenames, never relative traversal.
  if (std::string(name) != "request.json" && std::string(name) != "manifest.json" &&
      std::string(name) != "manifest.sig" && std::string(name) != "candidate" && std::string(name) != "candidate.sig") {
    throw std::runtime_error("Unsupported update request file.");
  }
  const int descriptor = openat(directory_.get(), name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
  if (descriptor < 0)
    throw std::runtime_error("Missing update input.");
  struct stat info{};
  if (fstat(descriptor, &info) != 0 || !S_ISREG(info.st_mode) || info.st_uid != owner_ || (info.st_mode & 077) != 0 ||
      info.st_nlink != 1) {
    close(descriptor);
    throw std::runtime_error("Unsafe update input ownership, permissions or file type.");
  }
  return descriptor;
}

std::string PrivateUpdateRequest::text(const char* name, std::size_t maximum) const {
  FileDescriptor input(open_file(name));
  return read_descriptor(input.get(), maximum);
}

} // namespace updates
} // namespace phonolite
