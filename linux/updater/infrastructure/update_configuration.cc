#include "infrastructure/update_configuration.h"

#include <cstdlib>
#include <stdexcept>

#include <sys/utsname.h>

#include "generated_configuration.h"
#include "infrastructure/package_manager.h"
#include "infrastructure/system_operations.h"
#include "infrastructure/update_json.h"

namespace phonolite {
namespace updates {
namespace {

std::string os_value(const std::string& source, const std::string& key) {
  const std::string prefix = key + "=";
  const auto position = source.find("\n" + prefix);
  const auto first = source.compare(0, prefix.size(), prefix) == 0 ? prefix.size()
                     : position == std::string::npos               ? std::string::npos
                                                                   : position + prefix.size() + 1;
  if (first == std::string::npos) {
    return "";
  }
  auto value = source.substr(first, source.find('\n', first) - first);
  if (value.size() >= 2 && value.front() == '"' && value.back() == '"') {
    value = value.substr(1, value.size() - 2);
  }
  return value;
}

} // namespace

UpdateConfiguration::UpdateConfiguration() {
  JsonDocument configuration(public_configuration);
  if (integer_value(configuration.object(), "schema") != 1 ||
      string_value(configuration.object(), "install_root") != "/opt/phonolite" ||
      string_value(configuration.object(), "helper_directory") != "/usr/libexec" ||
      string_value(configuration.object(), "launcher") != "/usr/bin/phonolite" ||
      string_value(configuration.object(), "package_name") != "phonolite") {
    throw std::runtime_error("Unsupported updater build configuration.");
  }
}

std::map<std::string, std::string> UpdateConfiguration::trusted_keys() const {
  JsonDocument configuration(public_configuration);
  JsonObject* keys = object_value(configuration.object(), "trusted_keys");
  std::map<std::string, std::string> result;
  GList* names = json_object_get_members(keys);
  for (GList* item = names; item != nullptr; item = item->next) {
    const auto* name = static_cast<const char*>(item->data);
    result.emplace(name, string_value(keys, name));
  }
  g_list_free(names);
  return result;
}

Installation UpdateConfiguration::installation() const {
  const std::string path = "/opt/phonolite/update-installation.json";
  require_protected_path(path);
  JsonDocument metadata(read_file(path));
  JsonObject* object = metadata.object();
  Installation result;
  result.target = string_value(object, "target");
  result.format = string_value(object, "format");
  result.architecture = string_value(object, "architecture");
  result.package_version = string_value(object, "package_version");
  result.managed = string_value(object, "ownership") == "github";
  if (integer_value(object, "schema") != 1 || !result.managed || result.architecture != "amd64") {
    throw std::runtime_error("This installation is not managed by Phonolite's GitHub updater.");
  }
  Version::parse(result.package_version);
  JsonDocument configuration(public_configuration);
  JsonArray* targets = array_value(configuration.object(), "targets");
  char* os_path = realpath("/etc/os-release", nullptr);
  if (os_path == nullptr)
    throw std::runtime_error("Cannot identify the distribution.");
  const std::string release_path(os_path);
  free(os_path);
  require_protected_path(release_path);
  const auto os = read_file(release_path, 65536);
  struct utsname system{};
  if (uname(&system) != 0 || std::string(system.machine) != "x86_64") {
    throw std::runtime_error("Unsupported processor architecture.");
  }
  for (guint index = 0; index < json_array_get_length(targets); ++index) {
    JsonObject* target = json_array_get_object_element(targets, index);
    if (target != nullptr && string_value(target, "id") == result.target &&
        string_value(target, "format") == result.format &&
        string_value(target, "architecture") == result.architecture &&
        string_value(target, "os_id") == os_value(os, "ID") &&
        (string_value(target, "os_version") == os_value(os, "VERSION_ID") ||
         (string_value(target, "os_version") == "rolling" && os_value(os, "ID") == "arch"))) {
      if (!boolean_value(target, "validated")) {
        throw std::runtime_error("Automatic updates are awaiting release validation for this target.");
      }
      require_installed_helpers();
      PackageManager(result.format, run_command).verify_installed(result, executable());
      return result;
    }
  }
  throw std::runtime_error("The installed package does not match a supported distribution target.");
}

std::string UpdateConfiguration::feed_url() const {
  JsonDocument configuration(public_configuration);
  return "https://github.com/" + string_value(configuration.object(), "repository") + "/releases/latest/download/" +
         string_value(configuration.object(), "manifest_asset");
}

std::string UpdateConfiguration::signature_url() const {
  JsonDocument configuration(public_configuration);
  return "https://github.com/" + string_value(configuration.object(), "repository") + "/releases/latest/download/" +
         string_value(configuration.object(), "signature_asset");
}

std::string UpdateConfiguration::executable() const {
  return "/opt/phonolite/phonolite_app";
}
std::string UpdateConfiguration::launcher() const {
  return "/usr/bin/phonolite";
}

void UpdateConfiguration::require_installed_helpers() const {
  if (trusted_keys().empty()) {
    throw std::runtime_error("Linux update signing has not been configured for this build.");
  }
  require_protected_path(executable());
  require_protected_path("/usr/libexec/phonolite-update-coordinator");
  require_protected_path("/usr/libexec/phonolite-update-installer");
  require_protected_path("/usr/share/polkit-1/actions/com.phonoliteorg.phonolite.update.policy");
}

} // namespace updates
} // namespace phonolite
