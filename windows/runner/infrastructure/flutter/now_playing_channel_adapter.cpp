#include "runner/infrastructure/flutter/now_playing_channel_adapter.h"

#include <utility>

#include <flutter/standard_method_codec.h>

#include "runner/infrastructure/flutter/now_playing_codec.h"
#include "runner/infrastructure/media/media_transport.h"

NowPlayingChannelAdapter::NowPlayingChannelAdapter(MediaTransport& transport) : transport_(transport) {}

NowPlayingChannelAdapter::~NowPlayingChannelAdapter() {
  detach();
}

void NowPlayingChannelAdapter::attach(flutter::BinaryMessenger& messenger) {
  if (channel_) {
    return;
  }

  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      &messenger, "phonolite/now_playing", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) { handle_call(call, std::move(result)); });
}

void NowPlayingChannelAdapter::detach() {
  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
    channel_.reset();
    transport_.clear();
  }
}

void NowPlayingChannelAdapter::dispatch_pending_commands() {
  const auto commands = transport_.take_commands();

  if (!channel_) {
    return;
  }

  for (const auto& command : commands) {
    channel_->InvokeMethod("remoteCommand", std::make_unique<flutter::EncodableValue>(encode_media_command(command)));
  }
}

void NowPlayingChannelAdapter::handle_call(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) const {
  if (call.method_name() == "clearNowPlaying") {
    if (transport_.clear()) {
      result->Success();
    } else {
      result->Error("media_clear_failed", "Windows could not clear the media session.");
    }

    return;
  }

  if (call.method_name() != "setNowPlaying") {
    result->NotImplemented();

    return;
  }

  const auto snapshot = decode_now_playing(call.arguments());

  if (!snapshot) {
    result->Error("invalid_now_playing", "A track and valid playback state are required.");

    return;
  }

  if (!transport_.publish(*snapshot)) {
    result->Error("media_update_failed", "Windows could not update the media session.");

    return;
  }

  result->Success();
}
