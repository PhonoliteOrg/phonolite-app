#ifndef PHONOLITE_TESTS_SUPPORT_TEST_BINARY_MESSENGER_H_
#define PHONOLITE_TESTS_SUPPORT_TEST_BINARY_MESSENGER_H_

#include <flutter_linux/flutter_linux.h>

G_DECLARE_FINAL_TYPE(TestBinaryMessenger, test_binary_messenger, TEST, BINARY_MESSENGER, GObject)

TestBinaryMessenger* test_binary_messenger_new();
bool test_binary_messenger_has_handler(TestBinaryMessenger* self);
int test_binary_messenger_response_count(TestBinaryMessenger* self);
void test_binary_messenger_fail_responses(TestBinaryMessenger* self, bool fail);
FlMethodResponse* test_binary_messenger_invoke(TestBinaryMessenger* self, const char* method, FlValue* arguments);

#endif // PHONOLITE_TESTS_SUPPORT_TEST_BINARY_MESSENGER_H_
