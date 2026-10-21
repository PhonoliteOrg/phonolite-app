#ifndef RUNNER_DATA_MODELS_DIRECTORIES_DIRECTORY_OPEN_RESULT_H_
#define RUNNER_DATA_MODELS_DIRECTORIES_DIRECTORY_OPEN_RESULT_H_

#include <cstdint>

struct DirectoryOpenResult {
  std::intptr_t native_status;

  bool is_accepted() const {
    return native_status > 32;
  }
};

#endif // RUNNER_DATA_MODELS_DIRECTORIES_DIRECTORY_OPEN_RESULT_H_
