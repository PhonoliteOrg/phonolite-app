#include "runner/infrastructure/flutter/now_playing_codec.h"

#include <algorithm>
#include <cmath>
#include <string>
#include <variant>

namespace {

using Value = flutter::EncodableValue;

const Value* field(const flutter::EncodableMap& map, const char* key) {
  const auto found = map.find(Value(key));

  return found == map.end() ? nullptr : &found->second;
}

std::string text(const flutter::EncodableMap& map, const char* key) {
  const auto* value = field(map, key);
  const auto* string = value ? std::get_if<std::string>(value) : nullptr;

  return string ? *string : std::string();
}

double number(const Value* value) {
  if (value) {
    if (const auto* real = std::get_if<double>(value)) {
      return *real;
    }

    if (const auto* integer = std::get_if<int32_t>(value)) {
      return *integer;
    }

    if (const auto* integer = std::get_if<int64_t>(value)) {
      return static_cast<double>(*integer);
    }
  }

  return 0;
}

int64_t milliseconds(const Value* value) {
  const double seconds = number(value);

  // Bound conversion well below overflow in Windows' 100ns TimeSpan ticks.
  return std::isfinite(seconds) ? static_cast<int64_t>(std::clamp(seconds, 0.0, 1.0e9) * 1000.0) : 0;
}

} // namespace

std::optional<NowPlayingSnapshot> decode_now_playing(const flutter::EncodableValue* value) {
  const auto* map = value ? std::get_if<flutter::EncodableMap>(value) : nullptr;

  if (!map) {
    return std::nullopt;
  }

  NowPlayingSnapshot snapshot;
  snapshot.track_id = text(*map, "trackId");
  const auto* playing = field(*map, "isPlaying");
  const auto* is_playing = playing ? std::get_if<bool>(playing) : nullptr;

  if (snapshot.track_id.empty() || !is_playing) {
    return std::nullopt;
  }

  snapshot.title = text(*map, "title");
  snapshot.artist = text(*map, "artist");
  snapshot.album = text(*map, "album");
  snapshot.artwork_key = text(*map, "artworkKey");
  snapshot.is_playing = *is_playing;
  snapshot.epoch = milliseconds(field(*map, "epoch")) / 1000;
  snapshot.duration_ms = milliseconds(field(*map, "duration"));
  snapshot.position_ms = std::min(milliseconds(field(*map, "position")), snapshot.duration_ms);

  if (const auto* bytes_value = field(*map, "artworkBytes")) {
    const auto* bytes = std::get_if<std::vector<uint8_t>>(bytes_value);

    if (!bytes || bytes->size() > 4 * 1024 * 1024) {
      return std::nullopt;
    }

    snapshot.artwork_bytes = *bytes;
  }

  return snapshot;
}

flutter::EncodableValue encode_media_command(const RemoteMediaCommand& command) {
  const char* type = "";

  switch (command.action) {
  case RemoteMediaAction::play:
    type = "play";
    break;
  case RemoteMediaAction::pause:
    type = "pause";
    break;
  case RemoteMediaAction::next:
    type = "next";
    break;
  case RemoteMediaAction::previous:
    type = "prev";
    break;
  case RemoteMediaAction::seek:
    type = "seek";
    break;
  }

  flutter::EncodableMap payload{{Value("type"), Value(type)}};

  if (command.action == RemoteMediaAction::seek) {
    payload.emplace(Value("position"), Value(command.position_seconds));
  }

  return Value(payload);
}
