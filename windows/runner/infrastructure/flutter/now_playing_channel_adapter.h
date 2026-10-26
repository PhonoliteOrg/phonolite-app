#ifndef RUNNER_INFRASTRUCTURE_FLUTTER_NOW_PLAYING_CHANNEL_ADAPTER_H_
#define RUNNER_INFRASTRUCTURE_FLUTTER_NOW_PLAYING_CHANNEL_ADAPTER_H_

#include <memory>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

class MediaTransport;

class NowPlayingChannelAdapter final {
 public:
  explicit NowPlayingChannelAdapter(MediaTransport& transport);
  ~NowPlayingChannelAdapter();

  NowPlayingChannelAdapter(const NowPlayingChannelAdapter&) = delete;
  NowPlayingChannelAdapter& operator=(const NowPlayingChannelAdapter&) = delete;
  NowPlayingChannelAdapter(NowPlayingChannelAdapter&&) = delete;
  NowPlayingChannelAdapter& operator=(NowPlayingChannelAdapter&&) = delete;

  void attach(flutter::BinaryMessenger& messenger);
  void detach();
  void dispatch_pending_commands();

 private:
  MediaTransport& transport_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  void handle_call(const flutter::MethodCall<flutter::EncodableValue>& call,
                   std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) const;
};

#endif // RUNNER_INFRASTRUCTURE_FLUTTER_NOW_PLAYING_CHANNEL_ADAPTER_H_
