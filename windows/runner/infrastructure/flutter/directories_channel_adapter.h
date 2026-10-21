#ifndef RUNNER_INFRASTRUCTURE_FLUTTER_DIRECTORIES_CHANNEL_ADAPTER_H_
#define RUNNER_INFRASTRUCTURE_FLUTTER_DIRECTORIES_CHANNEL_ADAPTER_H_

#include <memory>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

class DirectoryLauncher;

class DirectoriesChannelAdapter final {
 public:
  explicit DirectoriesChannelAdapter(DirectoryLauncher& launcher);
  ~DirectoriesChannelAdapter();

  DirectoriesChannelAdapter(const DirectoriesChannelAdapter&) = delete;
  DirectoriesChannelAdapter& operator=(const DirectoriesChannelAdapter&) = delete;
  DirectoriesChannelAdapter(DirectoriesChannelAdapter&&) = delete;
  DirectoriesChannelAdapter& operator=(DirectoriesChannelAdapter&&) = delete;

  void attach(flutter::BinaryMessenger& messenger);
  void detach();

 private:
  DirectoryLauncher& launcher_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  void handle_call(const flutter::MethodCall<flutter::EncodableValue>& call,
                   std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) const;
};

#endif // RUNNER_INFRASTRUCTURE_FLUTTER_DIRECTORIES_CHANNEL_ADAPTER_H_
