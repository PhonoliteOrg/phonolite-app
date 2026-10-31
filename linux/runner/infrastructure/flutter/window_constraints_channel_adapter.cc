#include "runner/infrastructure/flutter/window_constraints_channel_adapter.h"

#include <cmath>
#include <exception>
#include <utility>

#include "runner/infrastructure/flutter/method_response_sender.h"

namespace phonolite {
namespace {

bool read_dimension(FlValue* arguments, const char* name, int* result) {
  FlValue* value = fl_value_lookup_string(arguments, name);
  if (value == nullptr) {
    return false;
  }

  double dimension;
  if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT) {
    dimension = fl_value_get_float(value);
  } else if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) {
    dimension = static_cast<double>(fl_value_get_int(value));
  } else {
    return false;
  }

  if (!std::isfinite(dimension) || dimension <= 0 || dimension > G_MAXINT) {
    return false;
  }

  *result = static_cast<int>(std::ceil(dimension));

  return true;
}

} // namespace

WindowConstraintsChannelAdapter::WindowConstraintsChannelAdapter(MinimumContentSizeSetter set_minimum_content_size)
    : set_minimum_content_size_(std::move(set_minimum_content_size)) {}

WindowConstraintsChannelAdapter::~WindowConstraintsChannelAdapter() {
  detach();
}

void WindowConstraintsChannelAdapter::attach(FlBinaryMessenger* messenger) {
  if (registered_) {
    return;
  }

  g_return_if_fail(FL_IS_BINARY_MESSENGER(messenger));

  detach();

  messenger_ = FL_BINARY_MESSENGER(g_object_ref(messenger));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  channel_ = fl_method_channel_new(messenger_, "phonolite/window", FL_METHOD_CODEC(codec));
  registered_ = true;
  fl_method_channel_set_method_call_handler(channel_, method_call_cb, this, channel_closed_cb);
}

void WindowConstraintsChannelAdapter::detach() {
  if (channel_ == nullptr) {
    return;
  }

  // Remove the messenger-owned handler before its callback target is released.
  if (registered_) {
    fl_binary_messenger_set_message_handler_on_channel(messenger_, "phonolite/window", nullptr, nullptr, nullptr);
  }

  fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr, nullptr);
  g_clear_object(&channel_);
  g_clear_object(&messenger_);
  registered_ = false;
}

void WindowConstraintsChannelAdapter::method_call_cb(FlMethodChannel*, FlMethodCall* method_call, gpointer user_data) {
  auto* self = static_cast<WindowConstraintsChannelAdapter*>(user_data);
  g_autoptr(FlMethodResponse) response = nullptr;

  try {
    response = self->response_for_call(method_call);
  } catch (const std::exception& error) {
    g_warning("Failed to set window minimum: %s", error.what());
    response =
        FL_METHOD_RESPONSE(fl_method_error_response_new("resize_failed", "Could not set the window minimum.", nullptr));
  } catch (...) {
    g_warning("Failed to set window minimum: unknown native exception");
    response =
        FL_METHOD_RESPONSE(fl_method_error_response_new("resize_failed", "Could not set the window minimum.", nullptr));
  }

  g_autoptr(GError) error = nullptr;
  if (!send_method_response(method_call, response, &error)) {
    g_warning("Failed to send window response: %s", error != nullptr ? error->message : "Unknown transport failure.");
  }
}

void WindowConstraintsChannelAdapter::channel_closed_cb(gpointer user_data) {
  auto* self = static_cast<WindowConstraintsChannelAdapter*>(user_data);
  self->registered_ = false;
}

FlMethodResponse* WindowConstraintsChannelAdapter::response_for_call(FlMethodCall* method_call) const {
  if (g_strcmp0(fl_method_call_get_name(method_call), "setMinimumContentSize") != 0) {
    return FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  FlValue* arguments = fl_method_call_get_args(method_call);
  int width;
  int height;
  if (arguments == nullptr || fl_value_get_type(arguments) != FL_VALUE_TYPE_MAP ||
      !read_dimension(arguments, "width", &width) || !read_dimension(arguments, "height", &height)) {
    return FL_METHOD_RESPONSE(
        fl_method_error_response_new("invalid_size", "Positive finite window dimensions are required.", nullptr));
  }

  set_minimum_content_size_(width, height);

  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

} // namespace phonolite
