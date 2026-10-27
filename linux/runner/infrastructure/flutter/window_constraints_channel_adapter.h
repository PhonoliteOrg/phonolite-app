#ifndef PHONOLITE_RUNNER_INFRASTRUCTURE_FLUTTER_WINDOW_CONSTRAINTS_CHANNEL_ADAPTER_H_
#define PHONOLITE_RUNNER_INFRASTRUCTURE_FLUTTER_WINDOW_CONSTRAINTS_CHANNEL_ADAPTER_H_

#include <functional>

#include <flutter_linux/flutter_linux.h>

namespace phonolite {

class WindowConstraintsChannelAdapter {
 public:
  using MinimumContentSizeSetter = std::function<void(int, int)>;

  explicit WindowConstraintsChannelAdapter(MinimumContentSizeSetter set_minimum_content_size);
  ~WindowConstraintsChannelAdapter();

  WindowConstraintsChannelAdapter(const WindowConstraintsChannelAdapter&) = delete;
  WindowConstraintsChannelAdapter& operator=(const WindowConstraintsChannelAdapter&) = delete;

  void attach(FlBinaryMessenger* messenger);
  void detach();

 private:
  static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call, gpointer user_data);
  static void channel_closed_cb(gpointer user_data);

  FlMethodResponse* response_for_call(FlMethodCall* method_call) const;

  MinimumContentSizeSetter set_minimum_content_size_;
  FlBinaryMessenger* messenger_ = nullptr;
  FlMethodChannel* channel_ = nullptr;
  bool registered_ = false;
};

} // namespace phonolite

#endif // PHONOLITE_RUNNER_INFRASTRUCTURE_FLUTTER_WINDOW_CONSTRAINTS_CHANNEL_ADAPTER_H_
