#include "runner/infrastructure/media/windows_media_transport.h"

#include <algorithm>
#include <chrono>
#include <optional>
#include <utility>

#include <roapi.h>
#include <shcore.h>
#include <systemmediatransportcontrolsinterop.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>
#include <winrt/Windows.Storage.Streams.h>

#include "phonolite_app_identity.h"
#include "runner/infrastructure/media/media_command_queue.h"

namespace {

using namespace winrt::Windows::Media;
using namespace winrt::Windows::Storage::Streams;

RandomAccessStreamReference artwork_reference(const std::vector<uint8_t>& bytes) {
  // A bounded, in-memory IStream avoids async file I/O and blocking an STA on
  // StoreAsync(). Windows owns its own reference after publication.
  winrt::com_ptr<IStream> stream;
  winrt::check_hresult(::CreateStreamOnHGlobal(nullptr, TRUE, stream.put()));
  ULONG written = 0;
  winrt::check_hresult(stream->Write(bytes.data(), static_cast<ULONG>(bytes.size()), &written));
  winrt::check_bool(written == bytes.size());
  const LARGE_INTEGER start{};
  winrt::check_hresult(stream->Seek(start, STREAM_SEEK_SET, nullptr));

  IRandomAccessStream random{nullptr};
  winrt::check_hresult(::CreateRandomAccessStreamOverStream(
      stream.get(), BSOS_DEFAULT, winrt::guid_of<IRandomAccessStream>(), winrt::put_abi(random)));

  return RandomAccessStreamReference::CreateFromStream(random);
}

bool metadata_changed(const NowPlayingSnapshot& previous, const NowPlayingSnapshot& next) {
  return previous.track_id != next.track_id || previous.title != next.title || previous.artist != next.artist ||
         previous.album != next.album || previous.artwork_key != next.artwork_key ||
         previous.artwork_bytes != next.artwork_bytes;
}

} // namespace

struct WindowsMediaTransport::Impl {
  explicit Impl(HWND window) : window(window) {}

  HWND window;
  UINT message = 0;
  bool apartment_initialized = false;
  SystemMediaTransportControls controls{nullptr};
  winrt::event_token button_token{};
  winrt::event_token position_token{};
  bool button_subscribed = false;
  bool position_subscribed = false;
  std::shared_ptr<MediaCommandQueue> queue;
  std::optional<NowPlayingSnapshot> previous;

  void initialize() {
    if (controls) {
      return;
    }

    winrt::check_hresult(::RoInitialize(RO_INIT_SINGLETHREADED));
    apartment_initialized = true;
    message = ::RegisterWindowMessageW(L"Phonolite.SystemMediaTransport.Command");
    winrt::check_bool(message != 0);

    const auto interop =
        winrt::get_activation_factory<SystemMediaTransportControls, ISystemMediaTransportControlsInterop>();
    winrt::check_hresult(
        interop->GetForWindow(window, winrt::guid_of<SystemMediaTransportControls>(), winrt::put_abi(controls)));

    const HWND target_window = window;
    const UINT command_message = message;
    queue = std::make_shared<MediaCommandQueue>(
        [target_window, command_message]() { ::PostMessageW(target_window, command_message, 0, 0); });
    const std::weak_ptr<MediaCommandQueue> weak_queue = queue;

    button_token = controls.ButtonPressed([weak_queue](const auto&, const auto& args) noexcept {
      try {
        const auto pending = weak_queue.lock();

        if (!pending) {
          return;
        }

        switch (args.Button()) {
        case SystemMediaTransportControlsButton::Play:
          pending->push({RemoteMediaAction::play});
          break;
        case SystemMediaTransportControlsButton::Pause:
        case SystemMediaTransportControlsButton::Stop:
          pending->push({RemoteMediaAction::pause});
          break;
        case SystemMediaTransportControlsButton::Next:
          pending->push({RemoteMediaAction::next});
          break;
        case SystemMediaTransportControlsButton::Previous:
          pending->push({RemoteMediaAction::previous});
          break;
        default:
          break;
        }
      } catch (...) {
        // WinRT callback failures cannot unwind through the OS callback ABI.
      }
    });
    button_subscribed = true;

    position_token = controls.PlaybackPositionChangeRequested([weak_queue](const auto&, const auto& args) noexcept {
      try {
        if (const auto pending = weak_queue.lock()) {
          const double seconds = static_cast<double>(args.RequestedPlaybackPosition().count()) / 10000000.0;
          pending->push({RemoteMediaAction::seek, std::max(0.0, seconds)});
        }
      } catch (...) {
        // As above, never unwind through a Windows event callback.
      }
    });
    position_subscribed = true;

    controls.IsEnabled(false);
    controls.IsPlayEnabled(true);
    controls.IsPauseEnabled(true);
    controls.IsStopEnabled(true);
    controls.IsNextEnabled(true);
    controls.IsPreviousEnabled(true);
    controls.PlaybackRate(1.0);
  }

  void shutdown() noexcept {
    if (queue) {
      queue->deactivate();
    }

    // Removing callbacks before releasing the HWND/messenger is mandatory.
    // A callback already in flight only holds the synchronized queue.
    if (controls) {
      if (button_subscribed) {
        try {
          controls.ButtonPressed(button_token);
        } catch (...) {
        }
      }

      if (position_subscribed) {
        try {
          controls.PlaybackPositionChangeRequested(position_token);
        } catch (...) {
        }
      }

      try {
        controls.IsEnabled(false);
      } catch (...) {
      }
    }

    button_subscribed = false;
    position_subscribed = false;
    controls = nullptr;
    queue.reset();
    previous.reset();
    message = 0;

    if (apartment_initialized) {
      ::RoUninitialize();
      apartment_initialized = false;
    }
  }

  void publish(const NowPlayingSnapshot& snapshot) {
    initialize();

    if (!previous || metadata_changed(*previous, snapshot)) {
      const auto updater = controls.DisplayUpdater();
      updater.ClearAll();
      updater.Type(MediaPlaybackType::Music);
      updater.AppMediaId(phonolite_identity::app_id);
      const auto music = updater.MusicProperties();
      music.Title(winrt::to_hstring(snapshot.title));
      music.Artist(winrt::to_hstring(snapshot.artist));
      music.AlbumTitle(winrt::to_hstring(snapshot.album));

      if (!snapshot.artwork_bytes.empty()) {
        updater.Thumbnail(artwork_reference(snapshot.artwork_bytes));
      }

      updater.Update();
      previous = snapshot;
    }

    SystemMediaTransportControlsTimelineProperties timeline;
    timeline.StartTime(std::chrono::milliseconds(0));
    timeline.MinSeekTime(std::chrono::milliseconds(0));
    timeline.Position(std::chrono::milliseconds(snapshot.position_ms));
    timeline.MaxSeekTime(std::chrono::milliseconds(snapshot.duration_ms));
    timeline.EndTime(std::chrono::milliseconds(snapshot.duration_ms));
    controls.UpdateTimelineProperties(timeline);
    controls.PlaybackStatus(snapshot.is_playing ? MediaPlaybackStatus::Playing : MediaPlaybackStatus::Paused);
    queue->activate(snapshot.track_id, snapshot.epoch);
    controls.IsEnabled(true);
  }

  void clear() {
    if (queue) {
      queue->deactivate();
    }

    previous.reset();

    if (controls) {
      controls.IsEnabled(false);
      controls.PlaybackStatus(MediaPlaybackStatus::Closed);
      const auto updater = controls.DisplayUpdater();
      updater.ClearAll();
      updater.Update();
    }
  }
};

WindowsMediaTransport::WindowsMediaTransport(HWND window) : impl_(std::make_unique<Impl>(window)) {}

WindowsMediaTransport::~WindowsMediaTransport() {
  impl_->shutdown();
}

bool WindowsMediaTransport::is_command_message(UINT message) const {
  return impl_->message != 0 && message == impl_->message;
}

bool WindowsMediaTransport::publish(const NowPlayingSnapshot& snapshot) noexcept {
  try {
    impl_->publish(snapshot);

    return true;
  } catch (...) {
    impl_->shutdown();

    return false;
  }
}

bool WindowsMediaTransport::clear() noexcept {
  try {
    impl_->clear();

    return true;
  } catch (...) {
    impl_->shutdown();

    return false;
  }
}

std::vector<RemoteMediaCommand> WindowsMediaTransport::take_commands() {
  return impl_->queue ? impl_->queue->take() : std::vector<RemoteMediaCommand>();
}
