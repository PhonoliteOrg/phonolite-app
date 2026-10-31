#ifndef PHONOLITE_UPDATER_INFRASTRUCTURE_UPDATE_CONFIGURATION_H_
#define PHONOLITE_UPDATER_INFRASTRUCTURE_UPDATE_CONFIGURATION_H_

#include <map>
#include <string>

#include "data/models/update_types.h"

namespace phonolite {
namespace updates {

class UpdateConfiguration {
 public:
  UpdateConfiguration();
  std::map<std::string, std::string> trusted_keys() const;
  Installation installation() const;
  std::string feed_url() const;
  std::string signature_url() const;
  std::string executable() const;
  std::string launcher() const;
  void require_installed_helpers() const;
};

} // namespace updates
} // namespace phonolite
#endif
