#ifndef PHONOLITE_UPDATER_INFRASTRUCTURE_MANIFEST_VERIFIER_H_
#define PHONOLITE_UPDATER_INFRASTRUCTURE_MANIFEST_VERIFIER_H_

#include <ctime>
#include <map>
#include <string>

#include "data/models/update_types.h"

namespace phonolite {
namespace updates {

class ManifestVerifier {
 public:
  explicit ManifestVerifier(std::map<std::string, std::string> trusted_keys);

  Manifest verify(const std::string& manifest, const std::string& signatures, std::time_t now) const;
  static Asset select(const Manifest& manifest, const Installation& installation);
  static std::string asset_json(const Asset& asset, const Manifest& manifest);

 private:
  std::map<std::string, std::string> trusted_keys_;
};

} // namespace updates
} // namespace phonolite

#endif
