#include "runner/infrastructure/flutter/directories_channel_adapter.h"

#include <stdexcept>
#include <string>
#include <utility>

#include "runner/infrastructure/shell/directory_launcher.h"
#include "tests/support/test_binary_messenger.h"

namespace {

class ChannelFixture {
 public:
  explicit ChannelFixture(phonolite::DirectoryLauncher::UriLauncher launch_uri)
      : launcher_(std::move(launch_uri)), messenger_(test_binary_messenger_new()), adapter_(launcher_) {
    adapter_.attach(FL_BINARY_MESSENGER(messenger_));
  }

  ~ChannelFixture() {
    adapter_.detach();
    g_object_unref(messenger_);
  }

  TestBinaryMessenger* messenger() const {
    return messenger_;
  }

  phonolite::DirectoriesChannelAdapter& adapter() {
    return adapter_;
  }

  FlMethodResponse* invoke(FlValue* arguments, const char* method = "openDirectory") const {
    FlMethodResponse* response = test_binary_messenger_invoke(messenger_, method, arguments);
    g_assert_cmpint(test_binary_messenger_response_count(messenger_), ==, 1);
    return response;
  }

 private:
  phonolite::DirectoryLauncher launcher_;
  TestBinaryMessenger* messenger_;
  phonolite::DirectoriesChannelAdapter adapter_;
};

phonolite::DirectoryOpenResult accept_uri(const std::string&) {
  return phonolite::DirectoryOpenResult::accepted();
}

bool is_null(FlValue* value) {
  return value == nullptr || fl_value_get_type(value) == FL_VALUE_TYPE_NULL;
}

void assert_error(FlMethodResponse* response, const char* code, const char* message) {
  g_assert_true(FL_IS_METHOD_ERROR_RESPONSE(response));
  auto* error = FL_METHOD_ERROR_RESPONSE(response);
  g_assert_cmpstr(fl_method_error_response_get_code(error), ==, code);
  g_assert_cmpstr(fl_method_error_response_get_message(error), ==, message);
  g_assert_true(is_null(fl_method_error_response_get_details(error)));
}

void rejects_invalid_path(gconstpointer data) {
  const int kind = GPOINTER_TO_INT(data);
  g_autoptr(FlValue) arguments = nullptr;
  if (kind == 1) {
    arguments = fl_value_new_int(42);
  } else if (kind == 2) {
    arguments = fl_value_new_string("");
  } else if (kind == 3) {
    arguments = fl_value_new_string("relative/library");
  }

  int launches = 0;
  ChannelFixture fixture([&](const std::string&) {
    ++launches;
    return phonolite::DirectoryOpenResult::accepted();
  });

  g_autoptr(FlMethodResponse) response = fixture.invoke(arguments);

  assert_error(response, "invalid_path", "An absolute folder path is required.");
  g_assert_cmpint(launches, ==, 0);
}

void replies_success_after_native_acceptance() {
  std::string launched_uri;
  ChannelFixture fixture([&](const std::string& uri) {
    launched_uri = uri;
    return phonolite::DirectoryOpenResult::accepted();
  });
  g_autoptr(FlValue) arguments = fl_value_new_string("/tmp/My library/#favorite");

  g_autoptr(FlMethodResponse) response = fixture.invoke(arguments);

  g_assert_true(FL_IS_METHOD_SUCCESS_RESPONSE(response));
  g_assert_true(is_null(fl_method_success_response_get_result(FL_METHOD_SUCCESS_RESPONSE(response))));
  g_assert_cmpstr(launched_uri.c_str(), ==, "file:///tmp/My%20library/%23favorite");
}

void preserves_native_failure() {
  ChannelFixture fixture(
      [](const std::string&) { return phonolite::DirectoryOpenResult::failed("No desktop handler is configured."); });
  g_autoptr(FlValue) arguments = fl_value_new_string("/tmp/library");

  g_autoptr(FlMethodResponse) response = fixture.invoke(arguments);

  assert_error(response, "open_failed", "No desktop handler is configured.");
}

void unknown_method_does_not_launch() {
  int launches = 0;
  ChannelFixture fixture([&](const std::string&) {
    ++launches;
    return phonolite::DirectoryOpenResult::accepted();
  });
  g_autoptr(FlValue) arguments = fl_value_new_string("/tmp/library");

  g_autoptr(FlMethodResponse) response = fixture.invoke(arguments, "unsupported");

  g_assert_true(FL_IS_METHOD_NOT_IMPLEMENTED_RESPONSE(response));
  g_assert_cmpint(launches, ==, 0);
}

void contains_native_exceptions() {
  ChannelFixture fixture([](const std::string&) -> phonolite::DirectoryOpenResult {
    throw std::runtime_error("A native callback failed.");
  });
  g_autoptr(FlValue) arguments = fl_value_new_string("/tmp/library");

  g_test_expect_message(nullptr, G_LOG_LEVEL_WARNING, "*Failed to open folder*A native callback failed*");
  g_autoptr(FlMethodResponse) response = fixture.invoke(arguments);
  g_test_assert_expected_messages();

  assert_error(response, "open_failed", "Could not open the folder.");
}

void transport_failure_does_not_retry(gconstpointer data) {
  const int kind = GPOINTER_TO_INT(data);
  ChannelFixture fixture(accept_uri);
  test_binary_messenger_fail_responses(fixture.messenger(), true);
  g_autoptr(FlValue) arguments = fl_value_new_string(kind == 1 ? "relative/library" : "/tmp/library");

  g_test_expect_message(nullptr, G_LOG_LEVEL_WARNING, "*Failed to send folder response*test transport is closed*");
  g_autoptr(FlMethodResponse) response = fixture.invoke(arguments, kind == 2 ? "unsupported" : "openDirectory");
  g_test_assert_expected_messages();

  if (kind == 1) {
    assert_error(response, "invalid_path", "An absolute folder path is required.");
  } else if (kind == 2) {
    g_assert_true(FL_IS_METHOD_NOT_IMPLEMENTED_RESPONSE(response));
  } else {
    g_assert_true(FL_IS_METHOD_SUCCESS_RESPONSE(response));
  }
}

void detach_removes_handler_and_can_reattach() {
  ChannelFixture fixture(accept_uri);
  fixture.adapter().detach();
  fixture.adapter().detach();
  g_assert_false(test_binary_messenger_has_handler(fixture.messenger()));

  fixture.adapter().attach(FL_BINARY_MESSENGER(fixture.messenger()));
  g_autoptr(FlValue) arguments = fl_value_new_string("/tmp/library");
  g_autoptr(FlMethodResponse) response = fixture.invoke(arguments);
  g_assert_true(FL_IS_METHOD_SUCCESS_RESPONSE(response));
}

void repeated_attach_keeps_existing_binding() {
  ChannelFixture fixture(accept_uri);
  g_autoptr(TestBinaryMessenger) other_messenger = test_binary_messenger_new();

  fixture.adapter().attach(FL_BINARY_MESSENGER(other_messenger));

  g_assert_false(test_binary_messenger_has_handler(other_messenger));
  g_autoptr(FlValue) arguments = fl_value_new_string("/tmp/library");
  g_autoptr(FlMethodResponse) response = fixture.invoke(arguments);
  g_assert_true(FL_IS_METHOD_SUCCESS_RESPONSE(response));
}

void engines_have_independent_bindings() {
  int first_launches = 0;
  int second_launches = 0;
  ChannelFixture first([&](const std::string&) {
    ++first_launches;
    return phonolite::DirectoryOpenResult::accepted();
  });
  ChannelFixture second([&](const std::string&) {
    ++second_launches;
    return phonolite::DirectoryOpenResult::accepted();
  });
  g_autoptr(FlValue) arguments = fl_value_new_string("/tmp/library");

  g_autoptr(FlMethodResponse) response = second.invoke(arguments);

  g_assert_true(FL_IS_METHOD_SUCCESS_RESPONSE(response));
  g_assert_cmpint(first_launches, ==, 0);
  g_assert_cmpint(second_launches, ==, 1);
}

void old_adapter_does_not_remove_replacement() {
  ChannelFixture original(accept_uri);
  phonolite::DirectoryLauncher replacement_launcher([](const std::string&) {
    return phonolite::DirectoryOpenResult::failed("The replacement received this request.");
  });
  phonolite::DirectoriesChannelAdapter replacement(replacement_launcher);
  replacement.attach(FL_BINARY_MESSENGER(original.messenger()));

  original.adapter().detach();
  g_assert_true(test_binary_messenger_has_handler(original.messenger()));
  g_autoptr(FlValue) arguments = fl_value_new_string("/tmp/library");
  g_autoptr(FlMethodResponse) response = original.invoke(arguments);

  assert_error(response, "open_failed", "The replacement received this request.");
}

void closed_channel_can_reattach() {
  ChannelFixture fixture(accept_uri);
  fl_binary_messenger_set_message_handler_on_channel(FL_BINARY_MESSENGER(fixture.messenger()), "phonolite/directories",
                                                     nullptr, nullptr, nullptr);
  g_assert_false(test_binary_messenger_has_handler(fixture.messenger()));

  fixture.adapter().attach(FL_BINARY_MESSENGER(fixture.messenger()));
  g_autoptr(FlValue) arguments = fl_value_new_string("/tmp/library");
  g_autoptr(FlMethodResponse) response = fixture.invoke(arguments);
  g_assert_true(FL_IS_METHOD_SUCCESS_RESPONSE(response));
}

void destruction_releases_messenger() {
  gboolean finalized = FALSE;
  auto* messenger = test_binary_messenger_new();
  g_object_weak_ref(
      G_OBJECT(messenger), [](gpointer value, GObject*) { *static_cast<gboolean*>(value) = TRUE; }, &finalized);

  {
    phonolite::DirectoryLauncher launcher(accept_uri);
    phonolite::DirectoriesChannelAdapter adapter(launcher);
    adapter.attach(FL_BINARY_MESSENGER(messenger));
    g_object_unref(messenger);
  }

  g_assert_true(finalized);
}

} // namespace

int main(int argc, char** argv) {
  g_test_init(&argc, &argv, nullptr);
  g_test_add_data_func("/directories-channel/invalid/null", GINT_TO_POINTER(0), rejects_invalid_path);
  g_test_add_data_func("/directories-channel/invalid/type", GINT_TO_POINTER(1), rejects_invalid_path);
  g_test_add_data_func("/directories-channel/invalid/empty", GINT_TO_POINTER(2), rejects_invalid_path);
  g_test_add_data_func("/directories-channel/invalid/relative", GINT_TO_POINTER(3), rejects_invalid_path);
  g_test_add_func("/directories-channel/accepted", replies_success_after_native_acceptance);
  g_test_add_func("/directories-channel/native-failure", preserves_native_failure);
  g_test_add_func("/directories-channel/unknown-method", unknown_method_does_not_launch);
  g_test_add_func("/directories-channel/exception", contains_native_exceptions);
  g_test_add_data_func("/directories-channel/transport-failure/success", GINT_TO_POINTER(0),
                       transport_failure_does_not_retry);
  g_test_add_data_func("/directories-channel/transport-failure/error", GINT_TO_POINTER(1),
                       transport_failure_does_not_retry);
  g_test_add_data_func("/directories-channel/transport-failure/not-implemented", GINT_TO_POINTER(2),
                       transport_failure_does_not_retry);
  g_test_add_func("/directories-channel/detach-reattach", detach_removes_handler_and_can_reattach);
  g_test_add_func("/directories-channel/repeated-attach", repeated_attach_keeps_existing_binding);
  g_test_add_func("/directories-channel/independent-engines", engines_have_independent_bindings);
  g_test_add_func("/directories-channel/replacement", old_adapter_does_not_remove_replacement);
  g_test_add_func("/directories-channel/closed-reattach", closed_channel_can_reattach);
  g_test_add_func("/directories-channel/destruction", destruction_releases_messenger);
  return g_test_run();
}
