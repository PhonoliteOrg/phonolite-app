#ifndef RUNNER_INFRASTRUCTURE_MEDIA_WINDOWS_MEDIA_TRANSPORT_H_
#define RUNNER_INFRASTRUCTURE_MEDIA_WINDOWS_MEDIA_TRANSPORT_H_

#include <memory>

#include <windows.h>

#include "runner/infrastructure/media/media_transport.h"

/// Owns the HWND-associated SMTC session, WinRT apartment reference and event
/// subscriptions. Construction does no OS work; first publication initializes it.
class WindowsMediaTransport final : public MediaTransport {
 public:
  explicit WindowsMediaTransport(HWND window);
  ~WindowsMediaTransport() override;

  WindowsMediaTransport(const WindowsMediaTransport&) = delete;
  WindowsMediaTransport& operator=(const WindowsMediaTransport&) = delete;
  WindowsMediaTransport(WindowsMediaTransport&&) = delete;
  WindowsMediaTransport& operator=(WindowsMediaTransport&&) = delete;

  bool is_command_message(UINT message) const;
  bool publish(const NowPlayingSnapshot& snapshot) noexcept override;
  bool clear() noexcept override;
  std::vector<RemoteMediaCommand> take_commands() override;

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

#endif // RUNNER_INFRASTRUCTURE_MEDIA_WINDOWS_MEDIA_TRANSPORT_H_
