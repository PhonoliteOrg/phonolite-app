#ifndef PHONOLITE_UPDATER_DATA_MODELS_UPDATE_TYPES_H_
#define PHONOLITE_UPDATER_DATA_MODELS_UPDATE_TYPES_H_

#include <cstdint>
#include <map>
#include <string>
#include <vector>

namespace phonolite {
namespace updates {

struct Version {
  std::uint64_t major = 0;
  std::uint64_t minor = 0;
  std::uint64_t patch = 0;
  std::uint64_t revision = 0;

  static Version parse(const std::string& value);
  bool operator>(const Version& other) const;
};

struct Asset {
  std::string target;
  std::string format;
  std::string architecture;
  std::string package_version;
  std::string url;
  std::string sha256;
  std::uint64_t length = 0;
};

struct Installation {
  std::string target;
  std::string format;
  std::string architecture;
  std::string package_version;
  bool managed = false;
};

struct Manifest {
  std::string version;
  std::uint64_t revision = 0;
  std::string notes_url;
  std::vector<Asset> assets;
};

struct CommandResult {
  int exit_code = 0;
  std::string output;
  std::string error;
};

} // namespace updates
} // namespace phonolite

#endif
