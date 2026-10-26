#ifndef RUNNER_INFRASTRUCTURE_FLUTTER_NOW_PLAYING_CODEC_H_
#define RUNNER_INFRASTRUCTURE_FLUTTER_NOW_PLAYING_CODEC_H_

#include <optional>

#include <flutter/encodable_value.h>

#include "runner/data/models/media/now_playing_snapshot.h"

std::optional<NowPlayingSnapshot> decode_now_playing(const flutter::EncodableValue* value);
flutter::EncodableValue encode_media_command(const RemoteMediaCommand& command);

#endif // RUNNER_INFRASTRUCTURE_FLUTTER_NOW_PLAYING_CODEC_H_
