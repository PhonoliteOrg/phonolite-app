#include <cmath>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <memory>
#include <string>
#include <thread>
#include <utility>
#include <variant>
#include <vector>

#include <flutter/binary_messenger.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

#include "runner/infrastructure/flutter/now_playing_channel_adapter.h"
#include "runner/infrastructure/flutter/now_playing_codec.h"
#include "runner/infrastructure/media/media_command_queue.h"
#include "runner/infrastructure/media/media_transport.h"

namespace {

using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;

void require(bool condition, const char* description) {
  if (!condition) {
    std::cerr << "FAILED: " << description << '\n';
    std::exit(EXIT_FAILURE);
  }
}

Map snapshot_payload() {
  return {{Value("trackId"), Value("track")},    {Value("title"), Value(u8"A song \u00e9")},
          {Value("artist"), Value("Artist")},    {Value("album"), Value("Album")},
          {Value("epoch"), Value(int64_t{3})},   {Value("isPlaying"), Value(true)},
          {Value("duration"), Value(120.0)},     {Value("position"), Value(1.25)},
          {Value("artworkKey"), Value("cover")}, {Value("artworkBytes"), Value(std::vector<uint8_t>{1, 2, 3})}};
}

class TestTransport final : public MediaTransport {
 public:
  bool succeed = true;
  int publications = 0;
  int clears = 0;
  NowPlayingSnapshot last;
  std::vector<RemoteMediaCommand> commands;

  bool publish(const NowPlayingSnapshot& snapshot) noexcept override {
    ++publications;
    last = snapshot;

    return succeed;
  }

  bool clear() noexcept override {
    ++clears;
    commands.clear();

    return succeed;
  }

  std::vector<RemoteMediaCommand> take_commands() override {
    return std::exchange(commands, {});
  }
};

class TestMessenger final : public flutter::BinaryMessenger {
 public:
  flutter::BinaryMessageHandler handler;
  mutable std::vector<Map> commands;
  int attachments = 0;
  int detachments = 0;

  void Send(const std::string& channel, const uint8_t* bytes, size_t size, flutter::BinaryReply) const override {
    require(channel == "phonolite/now_playing", "Remote commands use the existing Now Playing channel");
    const auto call = flutter::StandardMethodCodec::GetInstance().DecodeMethodCall(bytes, size);
    require(call && call->method_name() == "remoteCommand", "Remote events retain their method name");
    commands.push_back(std::get<Map>(*call->arguments()));
  }

  void SetMessageHandler(const std::string& channel, flutter::BinaryMessageHandler next) override {
    require(channel == "phonolite/now_playing", "Attach to the existing Now Playing channel");
    next ? ++attachments : ++detachments;
    handler = std::move(next);
  }

  std::string call(const std::string& method, std::unique_ptr<Value> value = nullptr) {
    require(static_cast<bool>(handler), "Method calls need an attached handler");
    const auto& codec = flutter::StandardMethodCodec::GetInstance();
    const auto message = codec.EncodeMethodCall(flutter::MethodCall<Value>(method, std::move(value)));
    std::string outcome;
    int replies = 0;

    handler(message->data(), message->size(), [&](const uint8_t* response, size_t size) {
      ++replies;

      if (size == 0) {
        outcome = "not_implemented";

        return;
      }

      flutter::MethodResultFunctions<Value> result(
          [&](const Value*) { outcome = "success"; },
          [&](const std::string& code, const std::string&, const Value*) { outcome = code; },
          [&]() { outcome = "not_implemented"; });
      require(codec.DecodeAndProcessResponseEnvelope(response, size, &result), "Replies use the standard codec");
    });

    require(replies == 1, "Each method call gets exactly one response");

    return outcome;
  }
};

void verify_codec() {
  const Value valid(snapshot_payload());
  const auto snapshot = decode_now_playing(&valid);
  require(snapshot && snapshot->title == u8"A song \u00e9", "Unicode metadata survives transport decoding");
  require(snapshot->duration_ms == 120000 && snapshot->position_ms == 1250, "Seconds convert to native milliseconds");
  require(snapshot->epoch == 3 && snapshot->artwork_bytes == std::vector<uint8_t>({1, 2, 3}),
          "Snapshot epochs and PNG bytes survive decoding");
  require(!decode_now_playing(nullptr), "Missing snapshots are rejected");
  const Value wrong_type(4);
  require(!decode_now_playing(&wrong_type), "Scalar snapshots are rejected");

  auto invalid = snapshot_payload();
  invalid[Value("trackId")] = Value(3);
  const Value no_track(invalid);
  require(!decode_now_playing(&no_track), "Invalid track identities are rejected");
  invalid = snapshot_payload();
  invalid[Value("isPlaying")] = Value("yes");
  const Value no_state(invalid);
  require(!decode_now_playing(&no_state), "Invalid playback booleans are rejected");
  invalid = snapshot_payload();
  invalid[Value("artworkBytes")] = Value("not-bytes");
  const Value no_bytes(invalid);
  require(!decode_now_playing(&no_bytes), "Artwork must be typed bytes");

  auto bounds = snapshot_payload();
  bounds[Value("position")] = Value(9999.0);
  const Value past_end(bounds);
  require(decode_now_playing(&past_end)->position_ms == 120000, "Positions are bounded by duration");
  bounds[Value("duration")] = Value(std::numeric_limits<double>::infinity());
  const Value nonfinite(bounds);
  require(decode_now_playing(&nonfinite)->duration_ms == 0, "Nonfinite native timelines are rejected safely");

  const auto command = std::get<Map>(encode_media_command({RemoteMediaAction::seek, 12.5}));
  require(std::get<std::string>(command.at(Value("type"))) == "seek" &&
              std::get<double>(command.at(Value("position"))) == 12.5,
          "Native seeking returns seconds to the shared Dart coordinator");
}

void verify_queue() {
  int notifications = 0;
  MediaCommandQueue queue([&]() { ++notifications; });
  queue.push({RemoteMediaAction::play});
  require(notifications == 0 && queue.take().empty(), "No track means no global commands");
  queue.activate("first", 1);
  std::thread producer([&]() {
    queue.push({RemoteMediaAction::pause});
    queue.push({RemoteMediaAction::next});
  });
  producer.join();
  auto commands = queue.take();
  require(notifications == 1 && commands.size() == 2 && commands[0].action == RemoteMediaAction::pause &&
              commands[1].action == RemoteMediaAction::next,
          "Worker events preserve order and coalesce platform-thread wakeups");
  queue.push({RemoteMediaAction::seek, 20});
  queue.activate("second", 2);
  require(queue.take().empty(), "Track changes discard pending old-track commands");
  queue.push({RemoteMediaAction::play});
  queue.activate("second", 3);
  require(queue.take().empty(), "New playback epochs discard old seek/play commands");
  for (int i = 0; i < 100; ++i) {
    queue.push({RemoteMediaAction::next});
  }
  require(queue.take().size() == 64, "A stalled UI cannot grow the native command queue without bound");
  queue.push({RemoteMediaAction::play});
  queue.deactivate();
  const int previous_notifications = notifications;
  queue.push({RemoteMediaAction::pause});
  require(queue.take().empty() && notifications == previous_notifications,
          "Clear and teardown discard events and prevent later window notifications");
}

void verify_channel() {
  TestTransport transport;
  TestMessenger messenger;
  NowPlayingChannelAdapter adapter(transport);
  adapter.attach(messenger);
  adapter.attach(messenger);
  require(messenger.attachments == 1, "One messenger handler per media adapter");
  require(messenger.call("unrecognized") == "not_implemented", "Unknown methods retain their protocol response");
  require(messenger.call("setNowPlaying") == "invalid_now_playing", "Invalid snapshots never reach the OS");
  require(transport.publications == 0, "Validation happens before invoking native publication");
  require(messenger.call("setNowPlaying", std::make_unique<Value>(snapshot_payload())) == "success",
          "Valid snapshots publish to the borrowed capability");
  transport.succeed = false;
  require(messenger.call("setNowPlaying", std::make_unique<Value>(snapshot_payload())) == "media_update_failed",
          "Native publication failures are returned to Dart");
  transport.succeed = true;
  transport.commands = {{RemoteMediaAction::play},
                        {RemoteMediaAction::pause},
                        {RemoteMediaAction::next},
                        {RemoteMediaAction::previous},
                        {RemoteMediaAction::seek, 8.5}};
  adapter.dispatch_pending_commands();
  require(messenger.commands.size() == 5, "Every queued OS command is delivered once");
  require(std::get<std::string>(messenger.commands[3].at(Value("type"))) == "prev", "Previous retains the Dart action");
  require(std::get<double>(messenger.commands[4].at(Value("position"))) == 8.5, "Seek retains fractional seconds");
  adapter.dispatch_pending_commands();
  require(messenger.commands.size() == 5, "An empty drain never duplicates media events");
  require(messenger.call("clearNowPlaying") == "success", "Clear reaches the capability");
  adapter.detach();
  adapter.detach();
  require(messenger.detachments == 1 && transport.clears == 2, "Detach clears playback before releasing the messenger");
}

} // namespace

int main() {
  verify_codec();
  verify_queue();
  verify_channel();
  std::cout << "Windows media codec, callback queue and channel checks passed.\n";

  return EXIT_SUCCESS;
}
