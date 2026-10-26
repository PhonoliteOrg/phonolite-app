#include "runner/infrastructure/flutter/updates_channel_adapter.h"

#include <string>
#include <utility>

#include <flutter/standard_method_codec.h>

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

void UpdatesChannelAdapter::request_shutdown() {
  if (channel_ && available_) {
    channel_->InvokeMethod("shutdownForUpdate", nullptr);
  }
}

void UpdatesChannelAdapter::handle_call(const flutter::MethodCall<flutter::EncodableValue>& call,
                                        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  using Value = flutter::EncodableValue;
  if (call.method_name() == "initialize") {
    available_ = service_.initialize();
    result->Success(Value(flutter::EncodableMap{{Value("available"), Value(available_)},
                                                {Value("feedUrl"), Value(service_.feed_url())},
                                                {Value("currentVersion"), Value(service_.current_version())}}));
    return;
  }
  if (call.method_name() == "dispose") {
    service_.cleanup();
    available_ = false;
    result->Success();
    return;
  }
  if (call.method_name() != "showUpdate") {
    result->NotImplemented();
    return;
  }
  if (!available_) {
    result->Error("updates_unavailable", "Update checks are unavailable in this build.");
    return;
  }
  service_.show_update();
  result->Success();
}
