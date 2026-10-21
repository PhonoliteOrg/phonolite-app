#include <cstdlib>
#include <iostream>
#include <memory>
#include <string>
#include <type_traits>
#include <utility>
#include <variant>
#include <vector>

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

#include "runner/data/models/directories/directory_open_result.h"
#include "runner/data/models/window/window_geometry.h"
#include "runner/infrastructure/flutter/directories_channel_adapter.h"
#include "runner/infrastructure/shell/directory_launcher.h"
#include "runner/infrastructure/text/text_encoding.h"

namespace {

using Value = flutter::EncodableValue;

void require(bool condition, const char* description) {
  if (!condition) {
    std::cerr << "FAILED: " << description << '\n';
    std::exit(EXIT_FAILURE);
  }
}

struct ChannelReply {
  int reply_count = 0;
  bool not_implemented = false;
  std::string error_code;
  std::string error_message;
};

class TestMessenger final : public flutter::BinaryMessenger {
 public:
  void Send(const std::string&, const uint8_t*, size_t, flutter::BinaryReply) const override {
    require(false, "The incoming directory adapter must not send unsolicited messages");
  }

  void SetMessageHandler(const std::string& channel, flutter::BinaryMessageHandler handler) override {
    require(channel == "phonolite/directories", "Keep the existing directory channel name");

    if (handler) {
      ++attachments_;
    } else {
      ++detachments_;
    }

    handler_ = std::move(handler);
  }

  int attachments() const {
    return attachments_;
  }

  int detachments() const {
    return detachments_;
  }

  bool has_handler() const {
    return static_cast<bool>(handler_);
  }

  ChannelReply call(const std::string& method, std::unique_ptr<Value> argument) const {
    require(has_handler(), "Calls require an attached channel");

    const auto& codec = flutter::StandardMethodCodec::GetInstance();
    const auto message = codec.EncodeMethodCall(flutter::MethodCall<Value>(method, std::move(argument)));
    ChannelReply reply;

    handler_(message->data(), message->size(), [&reply, &codec](const uint8_t* bytes, size_t size) {
      ++reply.reply_count;

      if (size == 0) {
        reply.not_implemented = true;
        return;
      }

      flutter::MethodResultFunctions<Value> result(
          [](const Value*) { require(false, "Invalid directory requests must not succeed"); },
          [&reply](const std::string& code, const std::string& message, const Value* details) {
            reply.error_code = code;
            reply.error_message = message;
            require(details == nullptr || std::holds_alternative<std::monostate>(*details),
                    "Invalid-path errors have no native-status details");
          },
          [&reply]() { reply.not_implemented = true; });

      require(codec.DecodeAndProcessResponseEnvelope(bytes, size, &result), "The response must use the standard codec");
    });

    require(reply.reply_count == 1, "Each incoming method call receives exactly one reply");

    return reply;
  }

 private:
  flutter::BinaryMessageHandler handler_;
  int attachments_ = 0;
  int detachments_ = 0;
};

void verify_text_conversion() {
  const std::vector<std::string> paths = {"C:\\Music\\a folder", u8"C:\\Music\\\u00e9\\\u97f3\u697d\\\U0001f3b5",
                                          "relative/path"};

  for (const auto& path : paths) {
    const auto converted = utf16_from_utf8(path);

    require(converted.has_value(), "Valid UTF-8 paths convert to UTF-16");
    require(utf8_from_utf16(converted->c_str()) == path, "Unicode and path spelling survive the round trip");
  }

  require(utf8_from_utf16(nullptr).empty(), "A null UTF-16 input retains the empty result");
  require(utf8_from_utf16(L"").empty(), "An empty UTF-16 input retains the empty result");
  require(!utf16_from_utf8(""), "An empty UTF-8 input retains the failed conversion result");

  const std::vector<std::string> invalid = {"\xC3\x28", "\x80", "\xF0\x9F", "\xED\xA0\x80"};

  for (const auto& bytes : invalid) {
    require(!utf16_from_utf8(bytes), "Malformed UTF-8 is rejected without normalization");
  }

  const auto embedded_null = utf16_from_utf8(std::string("a\0b", 3));

  require(embedded_null && *embedded_null == std::wstring(L"a\0b", 3),
          "Length-based conversion preserves embedded null bytes");
}

void verify_values() {
  static_assert(std::is_same_v<decltype(WindowPoint::x), unsigned int>);
  static_assert(std::is_same_v<decltype(WindowSize::width), unsigned int>);

  const WindowPoint origin{10, 10};
  const WindowSize size{1280, 720};

  require(origin.x == 10 && origin.y == 10 && size.width == 1280 && size.height == 720,
          "Geometry retains the existing window defaults and unsigned units");

  for (std::intptr_t status : {-1, 0, 5, 31, 32}) {
    require(!DirectoryOpenResult{status}.is_accepted(), "Shell status values through 32 represent failure");
  }

  for (std::intptr_t status : {33, 64, 100}) {
    require(DirectoryOpenResult{status}.is_accepted(), "Shell status values above 32 represent acceptance");
  }
}

void verify_channel_and_lifetime() {
  TestMessenger messenger;
  DirectoryLauncher launcher(nullptr);

  {
    DirectoriesChannelAdapter adapter(launcher);
    adapter.attach(messenger);
    adapter.attach(messenger);

    require(messenger.attachments() == 1, "Repeated attachment keeps one handler");

    const auto unknown = messenger.call("unknown", nullptr);

    require(unknown.not_implemented && unknown.error_code.empty(), "Unknown methods retain NotImplemented replies");

    std::vector<std::unique_ptr<Value>> invalid_arguments;
    invalid_arguments.push_back(nullptr);
    invalid_arguments.push_back(std::make_unique<Value>());
    invalid_arguments.push_back(std::make_unique<Value>(42));
    invalid_arguments.push_back(std::make_unique<Value>(false));
    invalid_arguments.push_back(std::make_unique<Value>(std::string()));

    for (auto& argument : invalid_arguments) {
      const auto reply = messenger.call("openDirectory", std::move(argument));

      require(reply.error_code == "invalid_path" && reply.error_message == "A folder path is required.",
              "Missing, wrong-type and empty paths retain their exact error");
    }

    const auto invalid_utf8 = messenger.call("openDirectory", std::make_unique<Value>(std::string("\xC3\x28")));

    require(invalid_utf8.error_code == "invalid_path" &&
                invalid_utf8.error_message == "The folder path is not valid UTF-8.",
            "Malformed UTF-8 retains its distinct error");

    adapter.detach();
    adapter.detach();

    require(!messenger.has_handler() && messenger.detachments() == 1, "Detachment removes the handler once");

    adapter.attach(messenger);
    require(messenger.has_handler() && messenger.attachments() == 2, "An explicitly detached adapter can attach again");
  }

  require(!messenger.has_handler() && messenger.detachments() == 2,
          "Destruction unregisters the adapter while its messenger remains alive");
}

} // namespace

int main() {
  verify_text_conversion();
  verify_values();
  verify_channel_and_lifetime();

  std::cout
      << "Native text, value, channel and lifetime contracts passed without creating windows or opening folders.\n";

  return EXIT_SUCCESS;
}
