#include "tests/support/test_binary_messenger.h"

struct _TestBinaryMessenger {
  GObject parent_instance;

  FlBinaryMessengerMessageHandler handler;
  gpointer handler_data;
  GDestroyNotify destroy_notify;
  GBytes* response;
  int response_count;
  gboolean fail_responses;
};

static void test_binary_messenger_iface_init(FlBinaryMessengerInterface* iface);

G_DEFINE_TYPE_WITH_CODE(TestBinaryMessenger, test_binary_messenger, G_TYPE_OBJECT,
                        G_IMPLEMENT_INTERFACE(fl_binary_messenger_get_type(), test_binary_messenger_iface_init))

static void set_message_handler(FlBinaryMessenger* messenger, const gchar* channel,
                                FlBinaryMessengerMessageHandler handler, gpointer user_data,
                                GDestroyNotify destroy_notify) {
  auto* self = TEST_BINARY_MESSENGER(messenger);
  g_assert_cmpstr(channel, ==, "phonolite/directories");

  const auto previous_notify = self->destroy_notify;
  gpointer previous_data = self->handler_data;

  self->handler = handler;
  self->handler_data = user_data;
  self->destroy_notify = destroy_notify;

  if (previous_notify != nullptr) {
    previous_notify(previous_data);
  }
}

static gboolean send_response(FlBinaryMessenger* messenger, FlBinaryMessengerResponseHandle*, GBytes* response,
                              GError** error) {
  auto* self = TEST_BINARY_MESSENGER(messenger);
  ++self->response_count;
  g_clear_pointer(&self->response, g_bytes_unref);
  self->response = response != nullptr ? g_bytes_ref(response) : g_bytes_new(nullptr, 0);

  if (self->fail_responses) {
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_CLOSED, "The test transport is closed.");
    return FALSE;
  }

  return TRUE;
}

static void test_binary_messenger_dispose(GObject* object) {
  auto* self = TEST_BINARY_MESSENGER(object);
  set_message_handler(FL_BINARY_MESSENGER(self), "phonolite/directories", nullptr, nullptr, nullptr);
  g_clear_pointer(&self->response, g_bytes_unref);

  G_OBJECT_CLASS(test_binary_messenger_parent_class)->dispose(object);
}

static void test_binary_messenger_class_init(TestBinaryMessengerClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = test_binary_messenger_dispose;
}

static void test_binary_messenger_iface_init(FlBinaryMessengerInterface* iface) {
  iface->set_message_handler_on_channel = set_message_handler;
  iface->send_response = send_response;
}

static void test_binary_messenger_init(TestBinaryMessenger*) {}

TestBinaryMessenger* test_binary_messenger_new() {
  return TEST_BINARY_MESSENGER(g_object_new(test_binary_messenger_get_type(), nullptr));
}

bool test_binary_messenger_has_handler(TestBinaryMessenger* self) {
  return self->handler != nullptr;
}

int test_binary_messenger_response_count(TestBinaryMessenger* self) {
  return self->response_count;
}

void test_binary_messenger_fail_responses(TestBinaryMessenger* self, bool fail) {
  self->fail_responses = fail;
}

FlMethodResponse* test_binary_messenger_invoke(TestBinaryMessenger* self, const char* method, FlValue* arguments) {
  g_assert_nonnull(self->handler);
  self->response_count = 0;
  g_clear_pointer(&self->response, g_bytes_unref);

  g_autoptr(FlStandardMethodCodec) standard_codec = fl_standard_method_codec_new();
  auto* codec = FL_METHOD_CODEC(standard_codec);
  auto* codec_class = FL_METHOD_CODEC_GET_CLASS(codec);

  // Exercise the public codec vtable, without importing Flutter's private test headers.
  g_autoptr(GError) error = nullptr;
  g_autoptr(GBytes) request = codec_class->encode_method_call(codec, method, arguments, &error);
  g_assert_no_error(error);
  g_assert_nonnull(request);

  g_autoptr(FlBinaryMessengerResponseHandle) handle =
      FL_BINARY_MESSENGER_RESPONSE_HANDLE(g_object_new(fl_binary_messenger_response_handle_get_type(), nullptr));
  self->handler(FL_BINARY_MESSENGER(self), "phonolite/directories", request, handle, self->handler_data);
  g_assert_nonnull(self->response);

  FlMethodResponse* response = codec_class->decode_response(codec, self->response, &error);
  g_assert_no_error(error);
  g_assert_nonnull(response);
  return response;
}
