#include <cstdlib>
#include <iostream>
#include <memory>
#include <string>
#include <utility>
#include <variant>
#include <vector>

#include <flutter/binary_messenger.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

#include "runner/infrastructure/flutter/updates_channel_adapter.h"
#include "runner/infrastructure/updates/update_service.h"

namespace {

using Value = flutter::EncodableValue;

void require(bool condition, const char* description) {
  if (!condition) {
    std::cerr << description << '\n';
    std::exit(EXIT_FAILURE);
  }
}

class FakeUpdates final : public UpdateService {
 public:
  std::vector<std::string> calls;

  bool initialize() override {
    calls.push_back("initialize");
    return true;
  }
  std::string feed_url() const override {
    return "https://github.com/PhonoliteOrg/phonolite-app/releases/latest/download/windows-appcast.xml";
  }
  std::string current_version() const override {
    return "0.2.0.0";
  }
  void show_update() override {
    calls.push_back("show");
  }
  void cleanup() override {
    calls.push_back("cleanup");
  }
};

class Messenger final : public flutter::BinaryMessenger {
 public:
  mutable int shutdown_requests = 0;
  flutter::BinaryMessageHandler handler;
  mutable Value last_result;

  void Send(const std::string& channel, const uint8_t* message, size_t size, flutter::BinaryReply) const override {
    require(channel == "phonolite/updates", "Only the update channel is used");
    const auto call = flutter::StandardMethodCodec::GetInstance().DecodeMethodCall(message, size);
    require(call && call->method_name() == "shutdownForUpdate", "Installer requests graceful Dart shutdown");
    ++shutdown_requests;
  }

  void SetMessageHandler(const std::string& channel, flutter::BinaryMessageHandler value) override {
    require(channel == "phonolite/updates", "Keep a dedicated updater channel");
    handler = std::move(value);
  }

  std::string call(const std::string& method, std::unique_ptr<Value> argument = nullptr) const {
    const auto& codec = flutter::StandardMethodCodec::GetInstance();
    const auto bytes = codec.EncodeMethodCall(flutter::MethodCall<Value>(method, std::move(argument)));
    std::string status;
    int replies = 0;
    handler(bytes->data(), bytes->size(), [&](const uint8_t* response, size_t length) {
      ++replies;
      if (length == 0) {
        status = "not_implemented";
        return;
      }
      flutter::MethodResultFunctions<Value> result(
          [&](const Value* value) {
            status = "success";
            if (value != nullptr) {
              last_result = *value;
            }
          },
          [&](const std::string& code, const std::string&, const Value*) { status = code; },
          [&]() { status = "not_implemented"; });
      require(codec.DecodeAndProcessResponseEnvelope(response, length, &result), "Decode the standard reply");
    });
    require(replies == 1, "Every updater command completes once");
    return status;
  }
};

} // namespace

int main() {
  FakeUpdates service;
  Messenger messenger;
  UpdatesChannelAdapter adapter(service);
  adapter.attach(messenger);
  adapter.attach(messenger);
  require(service.calls.empty(), "Attaching a channel must not start networking or the updater");
  require(messenger.call("showUpdate") == "updates_unavailable", "Updater UI requires initialization");
  require(messenger.call("initialize") == "success", "Initialize the injected updater");
  const auto& configuration = std::get<flutter::EncodableMap>(messenger.last_result);
  require(std::get<std::string>(configuration.at(Value("feedUrl"))) == service.feed_url(),
          "Use the compiled feed URL for the quiet startup probe");
  require(std::get<std::string>(configuration.at(Value("currentVersion"))) == "0.2.0.0",
          "Compare against the native four-part build version");
  require(service.calls == std::vector<std::string>({"initialize"}), "Initialization must not open update UI");
  require(messenger.call("setAutomaticChecks") == "not_implemented", "There is no separate update switch");
  require(messenger.call("showUpdate") == "success", "Open updater UI only on explicit request");
  require(service.calls == std::vector<std::string>({"initialize", "show"}), "Do not initiate extra updater UI");
  adapter.request_shutdown();
  require(messenger.shutdown_requests == 1, "Update handoff reaches the Dart shutdown workflow");
  require(messenger.call("unknown") == "not_implemented", "Unknown updater calls remain unimplemented");
  require(messenger.call("dispose") == "success", "Stop updater operations explicitly");
  adapter.request_shutdown();
  require(messenger.shutdown_requests == 1, "Disposed updater cannot shut down the app");
  require(messenger.call("showUpdate") == "updates_unavailable", "Disposed updater rejects commands");
  adapter.detach();
  adapter.detach();
  require(!messenger.handler, "Detach removes the channel handler before messenger destruction");
  std::cout << "Updater transport contracts passed without starting WinSparkle or installing software.\n";
}
