#include <exception>
#include <iostream>

#include "application/installation_workflow.h"
#include "infrastructure/update_json.h"

int main(int argc, char** argv) {
  try {
    if (argc != 2) {
      throw std::runtime_error("Usage: phonolite-update-installer PRIVATE_REQUEST_DIRECTORY");
    }
    return phonolite::updates::install_update(argv[1]);
  } catch (const std::exception& error) {
    std::cout << "{\"event\":\"failed\",\"message\":" << phonolite::updates::json_string(error.what()) << "}"
              << std::endl;
    return 1;
  }
}
