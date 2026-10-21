#include "runner/infrastructure/flutter/directories_channel_adapter.h"

#include <exception>

#include "runner/infrastructure/shell/directory_launcher.h"

namespace phonolite {

DirectoriesChannelAdapter::DirectoriesChannelAdapter(const DirectoryLauncher& launcher) : launcher_(launcher) {}

DirectoriesChannelAdapter::~DirectoriesChannelAdapter() {
  detach();
}

void DirectoriesChannelAdapter::attach(FlBinaryMessenger* messenger) {
  if (registered_) {
    return;
  }

  g_return_if_fail(FL_IS_BINARY_MESSENGER(messenger));

  detach();

  messenger_ = FL_BINARY_MESSENGER(g_object_ref(messenger));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  channel_ = fl_method_channel_new(messenger_, "phonolite/directories", FL_METHOD_CODEC(codec));
  registered_ = true;
  fl_method_channel_set_method_call_handler(channel_, method_call_cb, this, channel_closed_cb);
}

void DirectoriesChannelAdapter::detach() {
  if (channel_ == nullptr) {
    return;
  }

  // FlMethodChannel is retained by its messenger until the binary handler is removed.
  // A replaced handler has already notified us; do not unregister its replacement.
  if (registered_) {
    fl_binary_messenger_set_message_handler_on_channel(messenger_, "phonolite/directories", nullptr, nullptr, nullptr);
  }

  fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr, nullptr);
  g_clear_object(&channel_);
  g_clear_object(&messenger_);
  registered_ = false;
}

void DirectoriesChannelAdapter::method_call_cb(FlMethodChannel*, FlMethodCall* method_call, gpointer user_data) {
  auto* self = static_cast<DirectoriesChannelAdapter*>(user_data);
  g_autoptr(FlMethodResponse) response = nullptr;

  try {
    response = self->response_for_call(method_call);
  } catch (const std::exception& error) {
    g_warning("Failed to open folder: %s", error.what());
    response = FL_METHOD_RESPONSE(fl_method_error_response_new("open_failed", "Could not open the folder.", nullptr));
  } catch (...) {
    g_warning("Failed to open folder: unknown native exception");
    response = FL_METHOD_RESPONSE(fl_method_error_response_new("open_failed", "Could not open the folder.", nullptr));
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to send folder response: %s", error != nullptr ? error->message : "Unknown transport failure.");
  }
}

void DirectoriesChannelAdapter::channel_closed_cb(gpointer user_data) {
  auto* self = static_cast<DirectoriesChannelAdapter*>(user_data);
  self->registered_ = false;
}

FlMethodResponse* DirectoriesChannelAdapter::response_for_call(FlMethodCall* method_call) const {
  if (g_strcmp0(fl_method_call_get_name(method_call), "openDirectory") != 0) {
    return FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  FlValue* arguments = fl_method_call_get_args(method_call);
  const gchar* path = arguments != nullptr && fl_value_get_type(arguments) == FL_VALUE_TYPE_STRING
                          ? fl_value_get_string(arguments)
                          : nullptr;
  if (path == nullptr || !g_path_is_absolute(path)) {
    return FL_METHOD_RESPONSE(
        fl_method_error_response_new("invalid_path", "An absolute folder path is required.", nullptr));
  }

  const DirectoryOpenResult result = launcher_.open_directory(path);
  if (result.is_accepted()) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }

  return FL_METHOD_RESPONSE(fl_method_error_response_new("open_failed", result.message.c_str(), nullptr));
}

} // namespace phonolite
