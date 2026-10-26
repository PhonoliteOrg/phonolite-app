#ifndef RUNNER_INFRASTRUCTURE_MEDIA_MEDIA_TRANSPORT_H_
#define RUNNER_INFRASTRUCTURE_MEDIA_MEDIA_TRANSPORT_H_

#include <vector>

#include "runner/data/models/media/now_playing_snapshot.h"

/// The channel borrows one transport. All operations run on the platform thread;
/// take_commands drains events marshalled from Windows' media callback threads.
class MediaTransport {
 public:
  virtual ~MediaTransport() = default;

  virtual bool publish(const NowPlayingSnapshot& snapshot) noexcept = 0;
  virtual bool clear() noexcept = 0;
  virtual std::vector<RemoteMediaCommand> take_commands() = 0;
};

#endif // RUNNER_INFRASTRUCTURE_MEDIA_MEDIA_TRANSPORT_H_
