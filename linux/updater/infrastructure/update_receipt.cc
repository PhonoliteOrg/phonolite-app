#include "infrastructure/update_receipt.h"

#include <stdexcept>

#include <unistd.h>

#include <glib/gstdio.h>

#include "infrastructure/system_operations.h"
#include "infrastructure/update_json.h"

namespace phonolite {
namespace updates {
namespace {
std::string result_directory() {
  return std::string(g_get_user_state_dir()) + "/phonolite";
}
} // namespace

void write_session_result(const std::string& correlation, const std::string& state, const std::string& version) {
  const auto directory = result_directory();
  if (getuid() == 0 || g_mkdir_with_parents(directory.c_str(), 0700) != 0) {
    throw std::runtime_error("Cannot create desktop update result storage.");
  }
  const auto source = "{\"schema\":1,\"correlation\":" + json_string(correlation) + ",\"state\":" + json_string(state) +
                      ",\"package_version\":" + json_string(version) + "}";
  if (!g_file_set_contents_full(
          (directory + "/update-result.json").c_str(), source.data(), source.size(),
          static_cast<GFileSetContentsFlags>(G_FILE_SET_CONTENTS_CONSISTENT | G_FILE_SET_CONTENTS_DURABLE), 0600,
          nullptr)) {
    throw std::runtime_error("Cannot persist the desktop update result.");
  }
}

std::string read_session_result() {
  const auto path = result_directory() + "/update-result.json";
  if (access(path.c_str(), F_OK) != 0)
    return "null";
  try {
    const auto source = read_file(path, 8192);
    JsonDocument document(source);
    return source;
  } catch (const std::exception&) {
    // User-session diagnostics cannot make package verification unavailable.
    return "null";
  }
}

} // namespace updates
} // namespace phonolite
