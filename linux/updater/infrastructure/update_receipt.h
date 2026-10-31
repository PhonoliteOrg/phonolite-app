#ifndef PHONOLITE_UPDATER_INFRASTRUCTURE_UPDATE_RECEIPT_H_
#define PHONOLITE_UPDATER_INFRASTRUCTURE_UPDATE_RECEIPT_H_

#include <string>

namespace phonolite {
namespace updates {

void write_session_result(const std::string& correlation, const std::string& state, const std::string& version);
std::string read_session_result();

} // namespace updates
} // namespace phonolite
#endif
