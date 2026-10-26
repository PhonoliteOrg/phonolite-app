#ifndef RUNNER_INFRASTRUCTURE_MEDIA_MEDIA_COMMAND_QUEUE_H_
#define RUNNER_INFRASTRUCTURE_MEDIA_MEDIA_COMMAND_QUEUE_H_

#include <functional>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

#include "runner/data/models/media/now_playing_snapshot.h"

/// Shared only with native event callbacks. Deactivation discards pending work
/// and prevents notification after its borrowed native window starts teardown.
class MediaCommandQueue final {
 public:
  explicit MediaCommandQueue(std::function<void()> notify) : notify_(std::move(notify)) {}

  void activate(const std::string& track_id, int64_t epoch) {
    const std::lock_guard<std::mutex> guard(mutex_);

    if (track_id_ != track_id || epoch_ != epoch) {
      commands_.clear();
    }

    track_id_ = track_id;
    epoch_ = epoch;
    active_ = true;
  }

  void deactivate() {
    const std::lock_guard<std::mutex> guard(mutex_);
    active_ = false;
    commands_.clear();
  }

  void push(RemoteMediaCommand command) {
    const std::lock_guard<std::mutex> guard(mutex_);

    if (!active_ || commands_.size() >= 64) {
      return;
    }

    const bool needs_notification = commands_.empty();
    commands_.push_back(command);

    // Notify under the same lock so deactivate synchronizes with the last post.
    if (needs_notification) {
      notify_();
    }
  }

  std::vector<RemoteMediaCommand> take() {
    const std::lock_guard<std::mutex> guard(mutex_);
    std::vector<RemoteMediaCommand> commands;
    commands.swap(commands_);

    return commands;
  }

 private:
  const std::function<void()> notify_;
  std::mutex mutex_;
  std::vector<RemoteMediaCommand> commands_;
  std::string track_id_;
  int64_t epoch_ = 0;
  bool active_ = false;
};

#endif // RUNNER_INFRASTRUCTURE_MEDIA_MEDIA_COMMAND_QUEUE_H_
