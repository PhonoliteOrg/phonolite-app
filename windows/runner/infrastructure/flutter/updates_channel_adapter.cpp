#include "runner/infrastructure/flutter/updates_channel_adapter.h"

#include <string>
#include <utility>

#include <flutter/standard_method_codec.h>

#include "runner/infrastructure/text/text_encoding.h"
#include "runner/infrastructure/updates/update_service.h"

UpdatesChannelAdapter::UpdatesChannelAdapter(UpdateService& service) : service_(service) {}

UpdatesChannelAdapter::~UpdatesChannelAdapter() {
  detach();
}

void UpdatesChannelAdapter::attach(flutter::BinaryMessenger& messenger) {
  if (channel_) {
    return;
  }
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      &messenger, "phonolite/updates", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const flutter::MethodCall<flutter::EncodableValue>& call,
                                        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    handle_call(call, std::move(result));
  });
}

void UpdatesChannelAdapter::detach() {
  if (!channel_) {
    return;
  }
  service_.cleanup();
  available_ = false;
  channel_->SetMethodCallHandler(nullptr);
  channel_.reset();
}

void UpdatesChannelAdapter::handle_call(const flutter::MethodCall<flutter::EncodableValue>& call,
                                        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  using Value = flutter::EncodableValue;
  if (call.method_name() == "initialize") {
    available_ = service_.initialize();
    result->Success(Value(flutter::EncodableMap{
        {Value("available"), Value(available_)},
        {Value("feedUrl"), Value(service_.feed_url())},
        {Value("currentVersion"), Value(service_.current_version())},
        {Value("publicKey"), Value(service_.public_key())},
        {Value("reason"),
         available_ ? Value() : Value("Automatic Windows updates require an installed release package.")}}));
    return;
  }
  if (call.method_name() == "dispose") {
    service_.cleanup();
    available_ = false;
    result->Success();
    return;
  }
  if (call.method_name() != "installUpdate" && call.method_name() != "stageUpdate" &&
      call.method_name() != "releaseUpdate") {
    result->NotImplemented();
    return;
  }
  if (!available_) {
    result->Error("updates_unavailable", "Update checks are unavailable in this build.");
    return;
  }
  if (call.method_name() == "releaseUpdate") {
    service_.release_update();
    result->Success();
    return;
  }
  unsigned long status = 0;
  if (call.method_name() == "stageUpdate") {
    const auto* arguments = call.arguments() ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
    const auto entry = arguments ? arguments->find(Value("path")) : flutter::EncodableMap::const_iterator{};
    const auto version_entry = arguments ? arguments->find(Value("version")) : flutter::EncodableMap::const_iterator{};
    const auto* path = arguments && entry != arguments->end() ? std::get_if<std::string>(&entry->second) : nullptr;
    const auto* version =
        arguments && version_entry != arguments->end() ? std::get_if<std::string>(&version_entry->second) : nullptr;
    const auto wide_path = path ? utf16_from_utf8(*path) : std::nullopt;
    if (!wide_path || wide_path->empty() || wide_path->find(L'\0') != std::wstring::npos || !version ||
        version->empty()) {
      result->Error("invalid_arguments", "A valid downloaded update path and version are required.");
      return;
    }
    status = service_.stage_update(*wide_path, *version);
  } else {
    status = service_.install_update();
  }
  if (status != 0) {
    result->Error("update_install_failed",
                  "Windows could not prepare or start the silent update (error " + std::to_string(status) + ").");
    return;
  }
  result->Success();
}
