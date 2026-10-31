#include "infrastructure/system_operations.h"

#include <cerrno>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <fstream>
#include <mutex>
#include <sstream>
#include <stdexcept>
#include <thread>

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <gio/gio.h>

namespace phonolite {
namespace updates {

FileDescriptor::FileDescriptor(int descriptor) : descriptor_(descriptor) {
  if (descriptor < 0) {
    throw std::runtime_error(std::string("Could not open update file: ") + std::strerror(errno));
  }
}

FileDescriptor::~FileDescriptor() {
  close(descriptor_);
}

int FileDescriptor::get() const {
  return descriptor_;
}

std::string read_descriptor(int descriptor, std::size_t maximum) {
  std::string result;
  char buffer[8192];
  ssize_t count;
  while ((count = read(descriptor, buffer, sizeof(buffer))) != 0) {
    if (count < 0) {
      if (errno == EINTR) {
        continue;
      }
      throw std::runtime_error("Could not read update file.");
    }
    if (result.size() + count > maximum) {
      throw std::runtime_error("Update file exceeds its size limit.");
    }
    result.append(buffer, count);
  }

  return result;
}

std::string read_file(const std::string& path, std::size_t maximum) {
  FileDescriptor descriptor(open(path.c_str(), O_RDONLY | O_NOFOLLOW | O_CLOEXEC));
  struct stat metadata{};
  if (fstat(descriptor.get(), &metadata) != 0 || !S_ISREG(metadata.st_mode)) {
    throw std::runtime_error("Update inputs must be regular files.");
  }

  return read_descriptor(descriptor.get(), maximum);
}

void require_protected_path(const std::string& path, bool directory) {
  if (path.empty() || path.front() != '/') {
    throw std::runtime_error("An absolute installed path is required.");
  }

  std::string current;
  std::istringstream components(path);
  std::string component;
  while (std::getline(components, component, '/')) {
    if (component.empty()) {
      continue;
    }
    if (component == "." || component == "..") {
      throw std::runtime_error("Installed paths must be canonical.");
    }
    current += "/" + component;
    struct stat metadata{};
    if (lstat(current.c_str(), &metadata) != 0 || metadata.st_uid != 0 || (metadata.st_mode & 0022) != 0 ||
        S_ISLNK(metadata.st_mode) || (current != path && !S_ISDIR(metadata.st_mode))) {
      throw std::runtime_error("Installed updater files must be root-owned and protected from modification.");
    }
    if (current == path && (directory ? !S_ISDIR(metadata.st_mode) : !S_ISREG(metadata.st_mode))) {
      throw std::runtime_error("Unexpected installed update file type.");
    }
  }
}

void copy_verified_package(int source, const std::string& destination, const Asset& asset) {
  FileDescriptor output(open(destination.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600));
  g_autoptr(GChecksum) checksum = g_checksum_new(G_CHECKSUM_SHA256);
  char buffer[65536];
  std::uint64_t total = 0;
  ssize_t count;
  while ((count = read(source, buffer, sizeof(buffer))) != 0) {
    if (count < 0) {
      if (errno == EINTR) {
        continue;
      }
      throw std::runtime_error("Could not read the downloaded package.");
    }
    total += count;
    if (total > asset.length) {
      throw std::runtime_error("Downloaded package exceeds the signed length.");
    }
    g_checksum_update(checksum, reinterpret_cast<const guchar*>(buffer), count);
    ssize_t written = 0;
    while (written < count) {
      const ssize_t amount = write(output.get(), buffer + written, count - written);
      if (amount < 0 && errno == EINTR) {
        continue;
      }
      if (amount <= 0) {
        throw std::runtime_error("Could not stage the update; check available disk space.");
      }
      written += amount;
    }
  }

  if (total != asset.length || asset.sha256 != g_checksum_get_string(checksum) || fsync(output.get()) != 0) {
    throw std::runtime_error("Downloaded package does not match its signed digest and length.");
  }
}

CommandResult run_command(const std::vector<std::string>& arguments, unsigned timeout_seconds) {
  if (arguments.empty() || arguments.front().empty() || arguments.front().front() != '/') {
    throw std::runtime_error("A fixed absolute update executable is required.");
  }

  std::vector<const gchar*> argv;
  for (const auto& argument : arguments) {
    argv.push_back(argument.c_str());
  }
  argv.push_back(nullptr);
  g_autoptr(GSubprocessLauncher) launcher = g_subprocess_launcher_new(
      static_cast<GSubprocessFlags>(G_SUBPROCESS_FLAGS_STDOUT_PIPE | G_SUBPROCESS_FLAGS_STDERR_PIPE));
  const gchar* environment[] = {"PATH=/usr/sbin:/usr/bin:/sbin:/bin", "LC_ALL=C", "DEBIAN_FRONTEND=noninteractive",
                                nullptr};
  g_subprocess_launcher_set_environ(launcher, const_cast<gchar**>(environment));
  g_autoptr(GError) error = nullptr;
  g_autoptr(GSubprocess) process = g_subprocess_launcher_spawnv(launcher, argv.data(), &error);
  if (process == nullptr) {
    throw std::runtime_error(std::string("Could not start package tool: ") + error->message);
  }

  g_autoptr(GCancellable) cancellation = g_cancellable_new();
  std::mutex mutex;
  std::condition_variable condition;
  bool completed = false;
  std::thread timer([&] {
    std::unique_lock<std::mutex> lock(mutex);
    if (timeout_seconds == 0) {
      condition.wait(lock, [&] { return completed; });
      return;
    }
    if (!condition.wait_for(lock, std::chrono::seconds(timeout_seconds), [&] { return completed; })) {
      g_cancellable_cancel(cancellation);
      g_subprocess_force_exit(process);
    }
  });
  g_autofree gchar* output = nullptr;
  g_autofree gchar* diagnostic = nullptr;
  const bool communicated = g_subprocess_communicate_utf8(process, nullptr, cancellation, &output, &diagnostic, &error);
  {
    std::lock_guard<std::mutex> lock(mutex);
    completed = true;
  }
  condition.notify_one();
  timer.join();
  if (!communicated) {
    throw std::runtime_error("The package tool failed or exceeded its operation deadline.");
  }

  CommandResult result;
  result.exit_code = g_subprocess_get_if_exited(process) ? g_subprocess_get_exit_status(process) : 128;
  result.output = output == nullptr ? "" : output;
  result.error = diagnostic == nullptr ? "" : diagnostic;
  if (result.output.size() + result.error.size() > 8 * 1024 * 1024) {
    throw std::runtime_error("Package tool output exceeded its limit.");
  }

  return result;
}

std::uint64_t process_start(pid_t process) {
  std::ifstream input("/proc/" + std::to_string(process) + "/stat");
  std::string line;
  std::getline(input, line);
  const auto end = line.rfind(')');
  if (!input || end == std::string::npos) {
    return 0;
  }

  std::istringstream fields(line.substr(end + 2));
  std::string value;
  for (int field = 3; field <= 22; ++field) {
    if (!(fields >> value)) {
      return 0;
    }
  }

  return std::stoull(value);
}

void require_application_process(pid_t process, uid_t owner, std::uint64_t start, const std::string& executable) {
  const std::string root = "/proc/" + std::to_string(process);
  struct stat metadata{};
  g_autofree gchar* actual = g_file_read_link((root + "/exe").c_str(), nullptr);
  if (process <= 1 || start == 0 || process_start(process) != start || stat(root.c_str(), &metadata) != 0 ||
      metadata.st_uid != owner || actual == nullptr || executable != actual) {
    throw std::runtime_error(
        "The update must belong to the running installed application. Restart an outdated instance first.");
  }
}

void wait_for_exit(pid_t process, std::uint64_t start, unsigned timeout_seconds) {
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(timeout_seconds);
  while (process_start(process) == start && std::chrono::steady_clock::now() < deadline) {
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
  }
  if (process_start(process) == start) {
    throw std::runtime_error("Phonolite did not exit before the installation deadline.");
  }
}

std::string installed_executable() {
  g_autofree gchar* path = g_file_read_link("/proc/self/exe", nullptr);
  return path == nullptr ? "" : path;
}

} // namespace updates
} // namespace phonolite
