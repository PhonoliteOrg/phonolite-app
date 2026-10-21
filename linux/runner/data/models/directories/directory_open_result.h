#ifndef PHONOLITE_RUNNER_DATA_MODELS_DIRECTORIES_DIRECTORY_OPEN_RESULT_H_
#define PHONOLITE_RUNNER_DATA_MODELS_DIRECTORIES_DIRECTORY_OPEN_RESULT_H_

#include <string>
#include <utility>

namespace phonolite {

enum class DirectoryOpenStatus { accepted, failed };

struct DirectoryOpenResult {
  DirectoryOpenStatus status;
  std::string message;

  static DirectoryOpenResult accepted() {
    return {DirectoryOpenStatus::accepted, {}};
  }

  static DirectoryOpenResult failed(std::string message) {
    return {DirectoryOpenStatus::failed, std::move(message)};
  }

  bool is_accepted() const {
    return status == DirectoryOpenStatus::accepted;
  }
};

} // namespace phonolite

#endif // PHONOLITE_RUNNER_DATA_MODELS_DIRECTORIES_DIRECTORY_OPEN_RESULT_H_
