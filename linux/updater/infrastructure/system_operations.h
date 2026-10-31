#ifndef PHONOLITE_UPDATER_INFRASTRUCTURE_SYSTEM_OPERATIONS_H_
#define PHONOLITE_UPDATER_INFRASTRUCTURE_SYSTEM_OPERATIONS_H_

#include <cstdint>
#include <string>
#include <vector>

#include <sys/types.h>

#include "data/models/update_types.h"

namespace phonolite {
namespace updates {

class FileDescriptor {
 public:
  explicit FileDescriptor(int descriptor);
  ~FileDescriptor();
  FileDescriptor(const FileDescriptor&) = delete;
  FileDescriptor& operator=(const FileDescriptor&) = delete;
  int get() const;

 private:
  int descriptor_;
};

std::string read_file(const std::string& path, std::size_t maximum = 1024 * 1024);
std::string read_descriptor(int descriptor, std::size_t maximum);
void require_protected_path(const std::string& path, bool directory = false);
void copy_verified_package(int source, const std::string& destination, const Asset& asset);
CommandResult run_command(const std::vector<std::string>& arguments, unsigned timeout_seconds = 60);
std::uint64_t process_start(pid_t process);
void require_application_process(pid_t process, uid_t owner, std::uint64_t start, const std::string& executable);
void wait_for_exit(pid_t process, std::uint64_t start, unsigned timeout_seconds);
std::string installed_executable();

} // namespace updates
} // namespace phonolite

#endif
