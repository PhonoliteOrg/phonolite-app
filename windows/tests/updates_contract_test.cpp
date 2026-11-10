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
  std::wstring installer;
  std::string version;
  unsigned long install_status = 0;

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
  std::string public_key() const override {
    return "compiled-public-key";
  }
  unsigned long stage_update(const std::wstring& path, const std::string& value) override {
    calls.push_back("stage");
    installer = path;
    version = value;
    return 0;
  }
  unsigned long install_update() override {
    calls.push_back("install");
    return install_status;
  }
  void release_update() override {
    calls.push_back("release");
  }
  void cleanup() override {
    calls.push_back("cleanup");
  }
};

class Messenger final : public flutter::BinaryMessenger {
 public:
  flutter::BinaryMessageHandler handler;
  mutable Value last_result;

  void Send(const std::string& channel, const uint8_t* message, size_t size, flutter::BinaryReply) const override {
    require(false, "Native updates must not request an unsolicited shutdown or open UI");
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
  require(messenger.call("installUpdate") == "updates_unavailable", "Installation requires initialization");
  require(messenger.call("initialize") == "success", "Initialize the injected updater");
  const auto& configuration = std::get<flutter::EncodableMap>(messenger.last_result);
  require(std::get<std::string>(configuration.at(Value("feedUrl"))) == service.feed_url(),
          "Use the compiled feed URL for the quiet startup probe");
  require(std::get<std::string>(configuration.at(Value("currentVersion"))) == "0.2.0.0",
          "Compare against the native four-part build version");
  require(std::get<std::string>(configuration.at(Value("publicKey"))) == service.public_key(),
          "Verify downloads against the compiled public key");
  require(std::holds_alternative<std::monostate>(configuration.at(Value("reason"))),
          "An available updater must not hide its status behind an empty disabled reason");
  require(service.calls == std::vector<std::string>({"initialize"}), "Initialization must not open update UI");
  require(messenger.call("setAutomaticChecks") == "not_implemented", "There is no separate update switch");
  require(messenger.call("showUpdate") == "not_implemented", "No native updater UI remains");
  require(messenger.call("stageUpdate") == "invalid_arguments", "Missing paths cannot stage installers");
  require(messenger.call("stageUpdate", std::make_unique<Value>(42)) == "invalid_arguments",
          "Reject an invalid argument type without launching anything");
  require(messenger.call("stageUpdate", std::make_unique<Value>(flutter::EncodableMap{
                                            {Value("path"), Value(std::string("bad\0path", 8))},
                                            {Value("version"), Value("0.3.0.1")}})) == "invalid_arguments",
          "Reject embedded nulls");
  require(service.calls.size() == 1, "Invalid arguments never reach the installer capability");
  auto installer = []() {
    return std::make_unique<Value>(flutter::EncodableMap{
        {Value("path"), Value("C:\\Temp\\Phonolite update\\update.exe")}, {Value("version"), Value("0.3.0.1")}});
  };
  require(messenger.call("stageUpdate", installer()) == "success", "Accept a downloaded update path");
  require(service.installer == L"C:\\Temp\\Phonolite update\\update.exe", "Preserve spaces in installer paths");
  require(service.version == "0.3.0.1", "Check the embedded installer version against the discovered release");
  require(messenger.call("installUpdate") == "success", "Start the previously staged installer");
  service.install_status = 5;
  require(messenger.call("installUpdate") == "update_install_failed",
          "Return process creation failures before Dart shuts the app down");
  require(messenger.call("releaseUpdate") == "success", "Cancellation can release a staged download");
  require(messenger.call("unknown") == "not_implemented", "Unknown updater calls remain unimplemented");
  require(messenger.call("dispose") == "success", "Stop updater operations explicitly");
  require(messenger.call("installUpdate") == "updates_unavailable", "Disposed updater rejects commands");
  adapter.detach();
  adapter.detach();
  require(!messenger.handler, "Detach removes the channel handler before messenger destruction");
  std::cout << "Updater transport contracts passed without installing software.\n";
}
