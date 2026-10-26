#ifndef RUNNER_INFRASTRUCTURE_FLUTTER_UPDATES_CHANNEL_ADAPTER_H_
#define RUNNER_INFRASTRUCTURE_FLUTTER_UPDATES_CHANNEL_ADAPTER_H_

#include <memory>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

class UpdateService;

class UpdatesChannelAdapter final {
 public:
  explicit UpdatesChannelAdapter(UpdateService& service);
  ~UpdatesChannelAdapter();

  UpdatesChannelAdapter(const UpdatesChannelAdapter&) = delete;
  UpdatesChannelAdapter& operator=(const UpdatesChannelAdapter&) = delete;

  void attach(flutter::BinaryMessenger& messenger);
  void detach();
  void request_shutdown();

 private:
  UpdateService& service_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  bool available_ = false;

  void handle_call(const flutter::MethodCall<flutter::EncodableValue>& call,
                   std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

#endif // RUNNER_INFRASTRUCTURE_FLUTTER_UPDATES_CHANNEL_ADAPTER_H_
