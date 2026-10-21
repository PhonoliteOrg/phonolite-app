#ifndef PHONOLITE_RUNNER_INFRASTRUCTURE_FLUTTER_DIRECTORIES_CHANNEL_ADAPTER_H_
#define PHONOLITE_RUNNER_INFRASTRUCTURE_FLUTTER_DIRECTORIES_CHANNEL_ADAPTER_H_

#include <flutter_linux/flutter_linux.h>

namespace phonolite {

class DirectoryLauncher;

class DirectoriesChannelAdapter {
 public:
  explicit DirectoriesChannelAdapter(const DirectoryLauncher& launcher);
  ~DirectoriesChannelAdapter();

  DirectoriesChannelAdapter(const DirectoriesChannelAdapter&) = delete;
  DirectoriesChannelAdapter& operator=(const DirectoriesChannelAdapter&) = delete;

  void attach(FlBinaryMessenger* messenger);
  void detach();

 private:
  static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call, gpointer user_data);
  static void channel_closed_cb(gpointer user_data);

  FlMethodResponse* response_for_call(FlMethodCall* method_call) const;

  const DirectoryLauncher& launcher_;
  FlBinaryMessenger* messenger_ = nullptr;
  FlMethodChannel* channel_ = nullptr;
  bool registered_ = false;
};

} // namespace phonolite

#endif // PHONOLITE_RUNNER_INFRASTRUCTURE_FLUTTER_DIRECTORIES_CHANNEL_ADAPTER_H_
