#ifndef PHONOLITE_UPDATER_APPLICATION_INSTALLATION_WORKFLOW_H_
#define PHONOLITE_UPDATER_APPLICATION_INSTALLATION_WORKFLOW_H_

#include <string>

namespace phonolite {
namespace updates {

int install_update(const std::string& request_directory);

} // namespace updates
} // namespace phonolite
#endif
