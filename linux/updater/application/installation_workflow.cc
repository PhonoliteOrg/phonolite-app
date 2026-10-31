#include "application/installation_workflow.h"

#include <cerrno>
#include <cstdlib>
#include <iostream>
#include <regex>
#include <stdexcept>

#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

#include "infrastructure/manifest_verifier.h"
#include "infrastructure/package_manager.h"
#include "infrastructure/system_operations.h"
#include "infrastructure/update_configuration.h"
#include "infrastructure/update_json.h"
#include "infrastructure/update_request.h"

namespace phonolite {
namespace updates {
namespace {

void ensure_directory(const std::string& path, mode_t mode) {
  if (mkdir(path.c_str(), mode) != 0 && errno != EEXIST) {
    throw std::runtime_error("Cannot create protected updater storage.");
  }
  require_protected_path(path, true);
  if (chmod(path.c_str(), mode) != 0)
    throw std::runtime_error("Cannot secure updater storage.");
}

void write_all(int descriptor, const std::string& source) {
  std::size_t offset = 0;
  while (offset < source.size()) {
    const auto count = write(descriptor, source.data() + offset, source.size() - offset);
    if (count < 0 && errno == EINTR) {
      continue;
    }
    if (count <= 0) {
      throw std::runtime_error("Cannot write updater result.");
    }
    offset += count;
  }
  if (fsync(descriptor) != 0) {
    throw std::runtime_error("Cannot persist updater result.");
  }
}

void receipt(uid_t owner, const std::string& correlation, const std::string& state, const std::string& version) {
  const std::string path = "/var/lib/phonolite-updates/receipt-" + std::to_string(owner) + ".json";
  const std::string temporary = path + ".tmp";
  // Only the root-owned transaction lock holder writes this root-owned directory.
  unlink(temporary.c_str());
  {
    FileDescriptor output(open(temporary.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0644));
    if (fchmod(output.get(), 0644) != 0)
      throw std::runtime_error("Cannot make update receipt readable.");
    write_all(output.get(), "{\"schema\":1,\"correlation\":" + json_string(correlation) + ",\"state\":" +
                                json_string(state) + ",\"package_version\":" + json_string(version) + "}\n");
  }
  if (rename(temporary.c_str(), path.c_str()) != 0) {
    throw std::runtime_error("Cannot commit updater result.");
  }
  FileDescriptor directory(open("/var/lib/phonolite-updates", O_RDONLY | O_DIRECTORY | O_CLOEXEC));
  if (fsync(directory.get()) != 0) {
    throw std::runtime_error("Cannot persist updater result directory.");
  }
}

class ProtectedStage {
 public:
  explicit ProtectedStage(const std::string& format) {
    extension_ = format == "deb" ? ".deb" : format == "rpm" ? ".rpm" : ".pkg.tar.zst";
    char path[] = "/var/lib/phonolite-updates/work-XXXXXX";
    if (mkdtemp(path) == nullptr) {
      throw std::runtime_error("Cannot create protected update staging.");
    }
    path_ = path;
  }
  ~ProtectedStage() {
    unlink(candidate().c_str());
    unlink((candidate() + ".sig").c_str());
    rmdir(path_.c_str());
  }
  std::string candidate() const {
    return path_ + "/candidate" + extension_;
  }

 private:
  std::string path_;
  std::string extension_;
};

} // namespace

int install_update(const std::string& request_directory) {
  if (geteuid() != 0) {
    throw std::runtime_error("The installer must be authorized through pkexec.");
  }
  const char* caller = getenv("PKEXEC_UID");
  if (caller == nullptr || !std::regex_match(caller, std::regex("[1-9][0-9]{0,9}"))) {
    throw std::runtime_error("Missing authenticated desktop user.");
  }
  const auto owner_value = std::stoull(caller);
  const uid_t owner = static_cast<uid_t>(owner_value);
  if (owner == 0 || owner != owner_value || request_directory.empty() || request_directory.front() != '/') {
    throw std::runtime_error("Invalid authenticated caller or request directory.");
  }
  PrivateUpdateRequest directory(request_directory, owner);
  const auto request = UpdateRequest::parse(directory.text("request.json", 8192));
  const auto process = request.process;
  const auto start = request.start;
  const auto correlation = request.correlation;
  UpdateConfiguration configuration;
  Installation installed = configuration.installation();
  if (request.expected_version != installed.package_version) {
    throw std::runtime_error("The installed version changed; check for updates again.");
  }
  require_application_process(process, owner, start, configuration.executable());
  ManifestVerifier verifier(configuration.trusted_keys());
  const auto manifest = verifier.verify(directory.text("manifest.json", 1024 * 1024),
                                        directory.text("manifest.sig", 8192), std::time(nullptr));
  const auto asset = ManifestVerifier::select(manifest, installed);
  if (!(Version::parse(asset.package_version) > Version::parse(installed.package_version))) {
    throw std::runtime_error("The selected release is not newer than the installed package.");
  }
  ensure_directory("/var/lib/phonolite-updates", 0755);
  FileDescriptor lock(
      open("/var/lib/phonolite-updates/transaction.lock", O_WRONLY | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0644));
  if (fchmod(lock.get(), 0644) != 0)
    throw std::runtime_error("Cannot expose updater lock status.");
  if (flock(lock.get(), LOCK_EX | LOCK_NB) != 0) {
    throw std::runtime_error("Another Phonolite update is already running.");
  }
  ProtectedStage stage(asset.format);
  FileDescriptor candidate(directory.open_file("candidate"));
  copy_verified_package(candidate.get(), stage.candidate(), asset);
  if (asset.format == "archlinux") {
    const auto signature = directory.text("candidate.sig", 65536);
    FileDescriptor output(open((stage.candidate() + ".sig").c_str(), O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600));
    write_all(output.get(), signature);
  }
  // The protected copy, never the caller's mutable file, is passed to native tools.
  PackageManager manager(asset.format, run_command);
  manager.verify_candidate(asset, stage.candidate());
  manager.preflight(stage.candidate());
  std::cout << "{\"event\":\"ready\",\"correlation\":" << json_string(correlation) << "}" << std::endl;
  std::string response;
  if (!std::getline(std::cin, response) || response != "install") {
    throw std::runtime_error("Update cancelled before application shutdown.");
  }
  wait_for_exit(process, start, 45);
  manager.verify_installed(installed, configuration.executable());
  receipt(owner, correlation, "interrupted", asset.package_version);
  try {
    std::cout << "{\"event\":\"installing\",\"correlation\":" << json_string(correlation) << "}" << std::endl;
    manager.install(stage.candidate());
    installed.package_version = asset.package_version;
    manager.verify_installed(installed, configuration.executable());
    receipt(owner, correlation, "succeeded", asset.package_version);
    std::cout << "{\"event\":\"succeeded\",\"correlation\":" << json_string(correlation) << "}" << std::endl;
  } catch (...) {
    receipt(owner, correlation, "failed", asset.package_version);
    throw;
  }
  return 0;
}

} // namespace updates
} // namespace phonolite
