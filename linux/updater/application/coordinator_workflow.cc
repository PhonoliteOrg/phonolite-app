#include "application/coordinator_workflow.h"

#include <chrono>
#include <iostream>
#include <stdexcept>
#include <thread>

#include <poll.h>
#include <unistd.h>

#include <gio/gio.h>

#include "infrastructure/system_operations.h"
#include "infrastructure/update_configuration.h"
#include "infrastructure/update_json.h"
#include "infrastructure/update_receipt.h"
#include "infrastructure/update_request.h"
#include "ui/update_window.h"

namespace phonolite {
namespace updates {
namespace {

std::string read_helper(GInputStream* stream, unsigned seconds) {
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(seconds);
  std::string line;
  auto* input = G_POLLABLE_INPUT_STREAM(stream);
  while (std::chrono::steady_clock::now() < deadline) {
    char character;
    g_autoptr(GError) error = nullptr;
    const auto count = g_pollable_input_stream_read_nonblocking(input, &character, 1, nullptr, &error);
    if (count == 0) {
      throw std::runtime_error("Authorization was cancelled or the installer connection closed. Check the native "
                               "package manager if installation had started.");
    }
    if (count < 0) {
      if (g_error_matches(error, G_IO_ERROR, G_IO_ERROR_WOULD_BLOCK)) {
        std::this_thread::sleep_for(std::chrono::milliseconds(25));
        continue;
      }
      throw std::runtime_error("Could not read the installer response.");
    }
    if (character == '\n') {
      if (!line.empty() && line.front() == '{') {
        return line;
      }
      line.clear();
    } else {
      line += character;
      if (line.size() > 65536) {
        throw std::runtime_error("Installer response exceeded its protocol limit.");
      }
    }
  }
  throw std::runtime_error("The updater exceeded its response deadline.");
}

std::string wait_prepared() {
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(60);
  std::string line;
  while (std::chrono::steady_clock::now() < deadline) {
    struct pollfd input{STDIN_FILENO, POLLIN, 0};
    if (poll(&input, 1, 100) > 0) {
      char character;
      if (read(STDIN_FILENO, &character, 1) != 1) {
        break;
      }
      if (character == '\n') {
        return line;
      }
      line += character;
      if (line.size() > 1024) {
        break;
      }
    }
  }
  throw std::runtime_error("Phonolite did not confirm successful shutdown preparation. No installation was started.");
}

void perform(const std::string& request_directory, UpdateWindow& window) {
  UpdateConfiguration configuration;
  configuration.installation();
  PrivateUpdateRequest directory(request_directory, getuid());
  const auto request = UpdateRequest::parse(directory.text("request.json", 8192));
  const auto pid = request.process;
  const auto start = request.start;
  require_application_process(pid, getuid(), start, configuration.executable());
  g_autoptr(GError) error = nullptr;
  g_autoptr(GSubprocess) helper = g_subprocess_new(
      static_cast<GSubprocessFlags>(G_SUBPROCESS_FLAGS_STDIN_PIPE | G_SUBPROCESS_FLAGS_STDOUT_PIPE |
                                    G_SUBPROCESS_FLAGS_STDERR_MERGE),
      &error, "/usr/bin/pkexec", "/usr/libexec/phonolite-update-installer", request_directory.c_str(), nullptr);
  if (helper == nullptr) {
    throw std::runtime_error("Could not start administrator authorization.");
  }
  bool committed = false;
  try {
    JsonDocument response(read_helper(g_subprocess_get_stdout_pipe(helper), 180));
    if (string_value(response.object(), "event") != "ready") {
      throw std::runtime_error(string_value(response.object(), "message"));
    }
    if (string_value(response.object(), "correlation") != request.correlation) {
      throw std::runtime_error("The installer responded to a different update request.");
    }
    window.update("Saving application state before installation…");
    std::cout << "{\"event\":\"ready\",\"correlation\":" << json_string(request.correlation) << "}" << std::endl;
    if (wait_prepared() != "prepared") {
      throw std::runtime_error("Application cleanup failed. No installation was started.");
    }
    gsize written = 0;
    if (!g_output_stream_write_all(g_subprocess_get_stdin_pipe(helper), "install\n", 8, &written, nullptr, &error)) {
      throw std::runtime_error("Could not commit installation readiness.");
    }
    committed = true;
    window.update("Waiting for Phonolite to exit, then installing the update…");
    for (;;) {
      JsonDocument event(read_helper(g_subprocess_get_stdout_pipe(helper), 1900));
      const auto name = string_value(event.object(), "event");
      if (name == "failed") {
        throw std::runtime_error(
            string_value(event.object(), "message") +
            " If installation began, inspect the native package manager before retrying; a rollback is not assumed.");
      }
      if (string_value(event.object(), "correlation") != request.correlation) {
        throw std::runtime_error("Mismatched installer response correlation.");
      }
      if (name == "succeeded") {
        break;
      }
      if (name != "installing") {
        throw std::runtime_error("Unexpected installer protocol response.");
      }
    }
    if (!g_subprocess_wait_check(helper, nullptr, &error)) {
      throw std::runtime_error("The installer did not confirm a successful exit.");
    }
  } catch (...) {
    // Closing stdin aborts an uncommitted helper. Never terminate a transaction
    // that may already be modifying the native package database.
    g_output_stream_close(g_subprocess_get_stdin_pipe(helper), nullptr, nullptr);
    if (!committed)
      g_subprocess_force_exit(helper);
    g_subprocess_wait(helper, nullptr, nullptr);
    throw;
  }
  const auto updated = configuration.installation();
  write_session_result(request.correlation, "relaunch-requested", updated.package_version);
  window.update("Update installed. Restarting Phonolite…");
  const char* arguments[] = {"/usr/bin/phonolite", nullptr};
  if (!g_spawn_async(nullptr, const_cast<gchar**>(arguments), nullptr, G_SPAWN_DEFAULT, nullptr, nullptr, nullptr,
                     &error)) {
    write_session_result(request.correlation, "relaunch-failed", updated.package_version);
    throw std::runtime_error(
        "The update was installed, but relaunch failed. Open Phonolite from the application menu.");
  }
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(60);
  while (std::chrono::steady_clock::now() < deadline) {
    JsonDocument receipt(read_session_result());
    if (string_value(receipt.object(), "correlation") == request.correlation &&
        string_value(receipt.object(), "state") == "succeeded") {
      window.update("Update installed. Phonolite restarted successfully under your desktop account.", true);
      return;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(250));
  }
  write_session_result(request.correlation, "relaunch-failed", updated.package_version);
  throw std::runtime_error("The update was installed, but Phonolite did not confirm startup. Open it from the "
                           "application menu and check its logs.");
}

} // namespace

int coordinate_update(const std::string& request_directory) {
  if (getuid() == 0 || geteuid() != getuid()) {
    throw std::runtime_error("Run the update coordinator as the desktop user.");
  }
  UpdateWindow window;
  window.present();
  int result = 0;
  std::thread worker([&] {
    try {
      perform(request_directory, window);
    } catch (const std::exception& error) {
      result = 1;
      std::cout << "{\"event\":\"failed\",\"message\":" << json_string(error.what()) << "}" << std::endl;
      window.update(error.what(), true);
    }
    for (const char* name : {"request.json", "manifest.json", "manifest.sig", "candidate", "candidate.sig"}) {
      unlink((request_directory + "/" + name).c_str());
    }
    rmdir(request_directory.c_str());
  });
  window.run();
  worker.join();
  return result;
}

} // namespace updates
} // namespace phonolite
