#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <glib.h>

#include "data/models/update_types.h"
#include "infrastructure/manifest_verifier.h"
#include "infrastructure/package_manager.h"
#include "infrastructure/system_operations.h"
#include "infrastructure/update_json.h"
#include "infrastructure/update_request.h"

using namespace phonolite::updates;
namespace {

void require(bool condition, const char* message) {
  if (!condition)
    throw std::runtime_error(message);
}

void rejects(const std::function<void()>& action) {
  bool rejected = false;
  try {
    action();
  } catch (const std::exception&) {
    rejected = true;
  }
  require(rejected, "Unsafe or invalid update input was accepted.");
}

void write_fixture(const std::string& path, const std::string& value) {
  require(g_file_set_contents(path.c_str(), value.data(), value.size(), nullptr), "Cannot write fixture.");
  require(chmod(path.c_str(), 0600) == 0, "Cannot secure fixture.");
}

void contracts() {
  require(Version::parse("1.0.0-2") > Version::parse("1.0.0-1"), "Revision ordering failed.");
  require(Version::parse("1.1.0-1") > Version::parse("1.0.99-99"), "Version ordering failed.");
  for (const char* value : {"1.0.0-0", "1.0.0-beta-1", "1.0-1", "-1.0.0-1", "2147483648.0.0-1"}) {
    rejects([&] { Version::parse(value); });
  }
  rejects([] { JsonDocument document("{\"x\":1,\"x\":2}"); });
  rejects([] { JsonDocument document("{\"a\":{\"x\":1,\"x\":2}}"); });
  rejects([] { JsonDocument document("[]"); });
  rejects([] { JsonDocument document(std::string(33, '[') + "0" + std::string(33, ']')); });
  rejects([] { wait_for_exit(getpid(), process_start(getpid()), 0); });
  rejects([] {
    UpdateRequest::parse(
        "{\"schema\":1,\"pid\":1,\"start\":2,\"correlation\":\"invalid\",\"expected_version\":\"1.0.0-1\"}");
  });
  const auto request = UpdateRequest::parse("{\"schema\":1,\"pid\":1234,\"start\":5,\"correlation\":"
                                            "\"0123456789abcdef0123456789abcdef\",\"expected_version\":\"1.0.0-1\"}");
  require(request.process == 1234 && request.start == 5, "Request decoding failed.");
  rejects([] { require_application_process(getpid(), getuid(), process_start(getpid()) + 1, installed_executable()); });
  rejects([] { require_application_process(getpid(), getuid() + 1, process_start(getpid()), installed_executable()); });
  require_application_process(getpid(), getuid(), process_start(getpid()), installed_executable());
  rejects([] { require_protected_path("/tmp"); });
  PackageManager deb("deb", [](const std::vector<std::string>& arguments, unsigned) {
    if (arguments[1] == "--simulate")
      return CommandResult{100, "", "Package database is locked"};
    return CommandResult{};
  });
  rejects([&] { deb.preflight("/protected/candidate.deb"); });
  require(deb.install_arguments("/protected/candidate.deb") ==
              std::vector<std::string>{"/usr/bin/apt-get", "-y", "--no-remove", "install", "/protected/candidate.deb"},
          "Unsafe Debian transaction.");
  PackageManager rpm("rpm",
                     [](const std::vector<std::string>&, unsigned) { return CommandResult{0, "digests OK", ""}; });
  rejects([&] { rpm.verify_candidate(Asset{}, "/protected/candidate.rpm"); });
  PackageManager arch("archlinux",
                      [](const std::vector<std::string>&, unsigned) { return CommandResult{0, "other-package", ""}; });
  rejects([&] { arch.preflight("/protected/candidate.pkg.tar.zst"); });
  require(arch.install_arguments("/protected/candidate.pkg.tar.zst") ==
              std::vector<std::string>{"/usr/bin/pacman", "-U", "--noconfirm", "/protected/candidate.pkg.tar.zst"},
          "Unsafe Arch invocation.");
  rejects([] { PackageManager("unknown", run_command); });
}

void staging() {
  char temporary[] = "/tmp/phonolite-native-test-XXXXXX";
  const std::string path = mkdtemp(temporary);
  write_fixture(path + "/candidate", "signed bytes");
  PrivateUpdateRequest request(path, getuid());
  require(request.text("candidate", 1024) == "signed bytes", "Cannot read private package fixture.");
  rejects([&] { request.text("../candidate", 1024); });
  rejects([&] { request.text("candidate", 2); });
  chmod((path + "/candidate").c_str(), 0644);
  rejects([&] { request.text("candidate", 1024); });
  chmod((path + "/candidate").c_str(), 0600);
  require(link((path + "/candidate").c_str(), (path + "/hardlink").c_str()) == 0, "Cannot link fixture.");
  rejects([&] { request.text("candidate", 1024); });
  unlink((path + "/hardlink").c_str());
  require(symlink((path + "/candidate").c_str(), (path + "/manifest.json").c_str()) == 0, "Cannot link fixture.");
  rejects([&] { request.text("manifest.json", 1024); });
  unlink((path + "/manifest.json").c_str());
  Asset asset;
  asset.length = 12;
  g_autofree gchar* digest = g_compute_checksum_for_string(G_CHECKSUM_SHA256, "signed bytes", -1);
  asset.sha256 = digest;
  {
    FileDescriptor source(request.open_file("candidate"));
    copy_verified_package(source.get(), path + "/protected", asset);
  }
  write_fixture(path + "/candidate", "changed data");
  require(read_file(path + "/protected") == "signed bytes", "Source mutation changed protected bytes.");
  {
    FileDescriptor source(request.open_file("candidate"));
    rejects([&] { copy_verified_package(source.get(), path + "/altered", asset); });
  }
  chmod(path.c_str(), 0755);
  rejects([&] { PrivateUpdateRequest unsafe(path, getuid()); });
  for (const char* name : {"candidate", "protected", "altered"})
    unlink((path + "/" + name).c_str());
  rmdir(path.c_str());
}

} // namespace

int main(int argc, char** argv) {
  try {
    if (argc == 4) {
      // Test executable only: release executables never accept caller-supplied keys.
      ManifestVerifier verifier({{"test", argv[1]}});
      const auto manifest = verifier.verify(read_file(argv[2]), read_file(argv[3]), std::time(nullptr));
      Installation installed{"ubuntu-26.04-amd64", "deb", "amd64", "0.1.0-1", true};
      const auto asset = ManifestVerifier::select(manifest, installed);
      std::cout << ManifestVerifier::asset_json(asset, manifest) << '\n';
      return 0;
    }
    contracts();
    staging();
    std::cout << "Updater contract and protected staging checks passed.\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
