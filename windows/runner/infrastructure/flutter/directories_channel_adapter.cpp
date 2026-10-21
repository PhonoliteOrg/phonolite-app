#include "runner/infrastructure/flutter/directories_channel_adapter.h"

#include <string>
#include <utility>
#include <variant>

#include <flutter/standard_method_codec.h>

#include "runner/infrastructure/shell/directory_launcher.h"
#include "runner/infrastructure/text/text_encoding.h"

DirectoriesChannelAdapter::DirectoriesChannelAdapter(DirectoryLauncher& launcher) : launcher_(launcher) {}

DirectoriesChannelAdapter::~DirectoriesChannelAdapter() {
  detach();
}

void DirectoriesChannelAdapter::attach(flutter::BinaryMessenger& messenger) {
  if (channel_) {
    return;
  }

  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      &messenger, "phonolite/directories", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const flutter::MethodCall<flutter::EncodableValue>& call,
                                        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    handle_call(call, std::move(result));
  });
}

void DirectoriesChannelAdapter::detach() {
  if (!channel_) {
    return;
  }

  channel_->SetMethodCallHandler(nullptr);
  channel_.reset();
}

void DirectoriesChannelAdapter::handle_call(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) const {
  if (call.method_name() != "openDirectory") {
    result->NotImplemented();

    return;
  }

  const auto* path = call.arguments() ? std::get_if<std::string>(call.arguments()) : nullptr;

  if (path == nullptr || path->empty()) {
    result->Error("invalid_path", "A folder path is required.");

    return;
  }

  const auto folder = utf16_from_utf8(*path);

  if (!folder) {
    result->Error("invalid_path", "The folder path is not valid UTF-8.");

    return;
  }

  const auto outcome = launcher_.open_directory(*folder);

  if (!outcome.is_accepted()) {
    result->Error("open_failed", "Could not open the folder.",
                  flutter::EncodableValue(static_cast<int>(outcome.native_status)));

    return;
  }

  result->Success();
}
