#include "runner/data/models/directories/directory_open_result.h"

#include <cstdlib>
#include <iostream>
#include <string>

namespace {

void require(bool condition, const char* description) {
  if (!condition) {
    std::cerr << description << '\n';
    std::exit(EXIT_FAILURE);
  }
}

} // namespace

int main() {
  const auto accepted = phonolite::DirectoryOpenResult::accepted();
  require(accepted.is_accepted() && accepted.message.empty(), "Accepted opening must not carry a failure message.");

  std::string native_message = "No application is registered for this URI.";
  const auto failed = phonolite::DirectoryOpenResult::failed(native_message);
  native_message.clear();
  require(!failed.is_accepted() && failed.message == "No application is registered for this URI.",
          "A failed opening must own its native message after the caller releases its copy.");

  auto copied = failed;
  copied.message = "A different failure.";
  require(failed.message == "No application is registered for this URI.",
          "Copied outcomes must own independent messages.");

  std::cout << "3 directory outcome checks passed. No platform SDK was used.\n";
  return EXIT_SUCCESS;
}
