#include "runner/infrastructure/shell/directory_launcher.h"

#include <utility>

#include <gio/gio.h>

namespace phonolite {
namespace {

DirectoryOpenResult launch_uri_with_gio(const std::string& uri) {
  g_autoptr(GError) error = nullptr;
  if (g_app_info_launch_default_for_uri(uri.c_str(), nullptr, &error)) {
    return DirectoryOpenResult::accepted();
  }

  return DirectoryOpenResult::failed(error != nullptr ? error->message : "Could not open the folder.");
}

} // namespace

DirectoryLauncher::DirectoryLauncher() : DirectoryLauncher(launch_uri_with_gio) {}

DirectoryLauncher::DirectoryLauncher(UriLauncher launch_uri) : launch_uri_(std::move(launch_uri)) {}

DirectoryOpenResult DirectoryLauncher::open_directory(const std::string& absolute_path) const {
  g_autoptr(GError) error = nullptr;
  g_autofree gchar* uri = g_filename_to_uri(absolute_path.c_str(), nullptr, &error);
  if (uri == nullptr) {
    return DirectoryOpenResult::failed(error != nullptr ? error->message : "Could not open the folder.");
  }

  return launch_uri_(uri);
}

} // namespace phonolite
