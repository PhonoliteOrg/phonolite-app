#include "runner/bootstrap/flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include <flutter/flutter_view_controller.h>

#include "runner/infrastructure/flutter/directories_channel_adapter.h"
#include "runner/infrastructure/flutter/now_playing_channel_adapter.h"
#include "runner/infrastructure/flutter/updates_channel_adapter.h"
#include "runner/infrastructure/media/windows_media_transport.h"
#include "runner/infrastructure/shell/directory_launcher.h"
#include "runner/infrastructure/updates/windows_update_service.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project) : project_(project) {}

FlutterWindow::~FlutterWindow() = default;

bool FlutterWindow::on_create() {
  if (!Win32Window::on_create()) {
    return false;
  }

  const RECT frame = get_client_area();

  // Match the native frame to avoid recreating the Flutter surface during startup.
  flutter_controller_ =
      std::make_unique<flutter::FlutterViewController>(frame.right - frame.left, frame.bottom - frame.top, project_);

  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }

  RegisterPlugins(flutter_controller_->engine());
  set_child_content(flutter_controller_->view()->GetNativeWindow());

  directory_launcher_ = std::make_unique<DirectoryLauncher>(get_handle());
  directory_channel_ = std::make_unique<DirectoriesChannelAdapter>(*directory_launcher_);
  directory_channel_->attach(*flutter_controller_->engine()->messenger());

  media_transport_ = std::make_unique<WindowsMediaTransport>(get_handle());
  now_playing_channel_ = std::make_unique<NowPlayingChannelAdapter>(*media_transport_);
  now_playing_channel_->attach(*flutter_controller_->engine()->messenger());

  update_service_ = std::make_unique<WindowsUpdateService>(get_handle());
  updates_channel_ = std::make_unique<UpdatesChannelAdapter>(*update_service_);
  updates_channel_->attach(*flutter_controller_->engine()->messenger());

  flutter_controller_->engine()->SetNextFrameCallback([this]() { show(); });

  // A first frame may already have completed before the callback was registered.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::on_destroy() {
  if (updates_channel_) {
    updates_channel_->detach();
  }
  updates_channel_.reset();
  update_service_.reset();

  if (now_playing_channel_) {
    now_playing_channel_->detach();
  }

  now_playing_channel_.reset();
  media_transport_.reset();

  if (directory_channel_) {
    directory_channel_->detach();
  }

  directory_channel_.reset();
  directory_launcher_.reset();
  flutter_controller_.reset();

  Win32Window::on_destroy();
}

LRESULT FlutterWindow::message_handler(HWND window, UINT message, WPARAM wparam, LPARAM lparam) noexcept {
  if (update_service_ && update_service_->is_shutdown_message(message)) {
    updates_channel_->request_shutdown();
    return 0;
  }

  if (media_transport_ && media_transport_->is_command_message(message)) {
    now_playing_channel_->dispatch_pending_commands();

    return 0;
  }

  if (flutter_controller_) {
    const std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(window, message, wparam, lparam);

    if (result) {
      return *result;
    }
  }

  switch (message) {
  case WM_FONTCHANGE:
    flutter_controller_->engine()->ReloadSystemFonts();
    break;
  }

  return Win32Window::message_handler(window, message, wparam, lparam);
}
