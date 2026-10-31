#include "data/models/update_types.h"

#include <regex>
#include <stdexcept>
#include <tuple>

namespace phonolite {
namespace updates {

Version Version::parse(const std::string& value) {
  std::smatch match;
  if (!std::regex_match(value, match, std::regex("([0-9]+)\\.([0-9]+)\\.([0-9]+)-([0-9]+)"))) {
    throw std::runtime_error("Unsupported package version; stable major.minor.patch-revision is required.");
  }

  Version result;
  result.major = std::stoull(match[1]);
  result.minor = std::stoull(match[2]);
  result.patch = std::stoull(match[3]);
  result.revision = std::stoull(match[4]);
  if (result.revision == 0 || result.major > 2147483647 || result.minor > 2147483647 || result.patch > 2147483647 ||
      result.revision > 2147483647) {
    throw std::runtime_error("Package version components are out of range.");
  }

  return result;
}

bool Version::operator>(const Version& other) const {
  return std::tie(major, minor, patch, revision) > std::tie(other.major, other.minor, other.patch, other.revision);
}

} // namespace updates
} // namespace phonolite
