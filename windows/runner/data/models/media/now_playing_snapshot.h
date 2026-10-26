#ifndef RUNNER_DATA_MODELS_MEDIA_NOW_PLAYING_SNAPSHOT_H_
#define RUNNER_DATA_MODELS_MEDIA_NOW_PLAYING_SNAPSHOT_H_

#include <cstdint>
#include <string>
#include <vector>

struct NowPlayingSnapshot {
  std::string track_id;
  std::string title;
  std::string artist;
  std::string album;
  std::string artwork_key;
  std::vector<uint8_t> artwork_bytes;
  int64_t epoch = 0;
  int64_t duration_ms = 0;
  int64_t position_ms = 0;
  bool is_playing = false;
};

enum class RemoteMediaAction { play, pause, next, previous, seek };

struct RemoteMediaCommand {
  RemoteMediaAction action;
  double position_seconds = 0;
};

#endif // RUNNER_DATA_MODELS_MEDIA_NOW_PLAYING_SNAPSHOT_H_
