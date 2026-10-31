#include <csignal>
#include <exception>
#include <iostream>
#include <string>

#include <unistd.h>

#include "application/coordinator_workflow.h"
#include "infrastructure/manifest_verifier.h"
#include "infrastructure/system_operations.h"
#include "infrastructure/update_configuration.h"
#include "infrastructure/update_json.h"
#include "infrastructure/update_receipt.h"

using phonolite::updates::JsonDocument;
using phonolite::updates::ManifestVerifier;
using phonolite::updates::UpdateConfiguration;

int main(int argc, char** argv) {
  using namespace phonolite::updates;
  std::signal(SIGPIPE, SIG_IGN);
  try {
    UpdateConfiguration configuration;
    if (argc == 2 && std::string(argv[1]) == "--describe") {
      try {
        const auto installed = configuration.installation();
        std::cout << "{\"available\":true,\"currentVersion\":" << json_string(installed.package_version)
                  << ",\"feedUrl\":" << json_string(configuration.feed_url())
                  << ",\"signatureUrl\":" << json_string(configuration.signature_url());
        const auto receipt_path = "/var/lib/phonolite-updates/receipt-" + std::to_string(getuid()) + ".json";
        if (access(receipt_path.c_str(), F_OK) == 0) {
          require_protected_path(receipt_path);
          const auto source = read_file(receipt_path, 8192);
          JsonDocument receipt(source);
          std::cout << ",\"receipt\":" << source;
        }
        std::cout << ",\"sessionResult\":" << read_session_result() << "}" << std::endl;
      } catch (const std::exception& error) {
        std::cout << "{\"available\":false,\"reason\":" << json_string(error.what()) << "}" << std::endl;
      }
      return 0;
    }
    if (argc == 3 && std::string(argv[1]) == "--acknowledge-relaunch") {
      const auto installed = configuration.installation();
      JsonDocument receipt(read_session_result());
      if (string_value(receipt.object(), "correlation") != argv[2] ||
          string_value(receipt.object(), "package_version") != installed.package_version) {
        throw std::runtime_error("The restarted application does not match this update result.");
      }
      write_session_result(argv[2], "succeeded", installed.package_version);
      std::cout << "{\"acknowledged\":true}" << std::endl;
      return 0;
    }
    if (argc == 3 && std::string(argv[1]) == "--coordinate") {
      return coordinate_update(argv[2]);
    }
    if (argc == 4 && (std::string(argv[1]) == "--select" || std::string(argv[1]) == "--verify-manifest")) {
      ManifestVerifier verifier(configuration.trusted_keys());
      const auto manifest = verifier.verify(read_file(argv[2]), read_file(argv[3], 8192), std::time(nullptr));
      if (std::string(argv[1]) == "--verify-manifest") {
        std::cout << "{\"verified\":true}" << std::endl;
      } else {
        const auto installed = configuration.installation();
        const auto asset = ManifestVerifier::select(manifest, installed);
        if (Version::parse(asset.package_version) > Version::parse(installed.package_version)) {
          std::cout << ManifestVerifier::asset_json(asset, manifest) << std::endl;
        } else {
          std::cout << "null" << std::endl;
        }
      }
      return 0;
    }
    throw std::runtime_error("Unsupported updater command or argument count.");
  } catch (const std::exception& error) {
    std::cerr << error.what() << std::endl;
    return 1;
  }
}
