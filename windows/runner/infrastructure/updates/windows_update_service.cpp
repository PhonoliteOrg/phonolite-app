#include "runner/infrastructure/updates/windows_update_service.h"

#include <atomic>
#include <string>

#include <winsparkle.h>

#include "phonolite_app_identity.h"
#include "phonolite_updates.h"

namespace {

std::atomic<HWND> shutdown_window{nullptr};

UINT shutdown_message() {
  static const UINT message = RegisterWindowMessageW(L"Phonolite.WinSparkle.Shutdown");
  return message;
}

#ifndef _DEBUG
void __cdecl request_shutdown() {
  const HWND window = shutdown_window.load();
  if (window != nullptr) {
    PostMessageW(window, shutdown_message(), 0, 0);
  }
}
#endif

} // namespace

WindowsUpdateService::WindowsUpdateService(HWND owner_window) : owner_window_(owner_window) {}

WindowsUpdateService::~WindowsUpdateService() {
  cleanup();
}

bool WindowsUpdateService::initialize() {
#ifdef _DEBUG
  return false;
#else
  if (initialized_) {
    return true;
  }
  if (shutdown_message() == 0 || !win_sparkle_set_eddsa_public_key(phonolite_updates::public_key)) {
    return false;
  }
  const std::string build = current_version();
  const std::wstring version(build.begin(), build.end());
  win_sparkle_set_app_details(L"PhonoliteOrg", phonolite_identity::display_name, version.c_str());
  win_sparkle_set_app_build_version(version.c_str());
  win_sparkle_set_registry_path("Software\\PhonoliteOrg\\Phonolite\\Updates");
  win_sparkle_set_appcast_url(phonolite_updates::feed_url);
  // Dart probes the feed quietly at every startup. WinSparkle UI opens only from the update tile.
  win_sparkle_set_automatic_check_for_updates(0);
  shutdown_window.store(owner_window_);
  win_sparkle_set_shutdown_request_callback(request_shutdown);
  win_sparkle_init();
  initialized_ = true;
  return true;
#endif
}

std::string WindowsUpdateService::feed_url() const {
  return phonolite_updates::feed_url;
}

std::string WindowsUpdateService::current_version() const {
  return std::to_string(FLUTTER_VERSION_MAJOR) + "." + std::to_string(FLUTTER_VERSION_MINOR) + "." +
         std::to_string(FLUTTER_VERSION_PATCH) + "." + std::to_string(FLUTTER_VERSION_BUILD);
}

bool WindowsUpdateService::is_shutdown_message(UINT message) const {
  return initialized_ && message == shutdown_message();
}

void WindowsUpdateService::show_update() {
  if (initialized_) {
    win_sparkle_check_update_with_ui();
  }
}

void WindowsUpdateService::cleanup() {
  if (!initialized_) {
    return;
  }
  shutdown_window.store(nullptr);
  win_sparkle_set_shutdown_request_callback(nullptr);
  win_sparkle_cleanup();
  initialized_ = false;
}
