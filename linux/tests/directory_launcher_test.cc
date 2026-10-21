#include "runner/infrastructure/shell/directory_launcher.h"

#include <string>

#include <gio/gio.h>

namespace {

void converts_and_escapes_native_filename() {
  std::string launched_uri;
  phonolite::DirectoryLauncher launcher([&](const std::string& uri) {
    launched_uri = uri;
    return phonolite::DirectoryOpenResult::accepted();
  });

  const auto result = launcher.open_directory("/tmp/Phonolite folders/#mix?");

  g_assert_true(result.is_accepted());
  g_assert_cmpstr(launched_uri.c_str(), ==, "file:///tmp/Phonolite%20folders/%23mix%3F");
}

void returns_native_launch_failure() {
  phonolite::DirectoryLauncher launcher(
      [](const std::string&) { return phonolite::DirectoryOpenResult::failed("The desktop rejected this request."); });

  const auto result = launcher.open_directory("/tmp/library");

  g_assert_false(result.is_accepted());
  g_assert_cmpstr(result.message.c_str(), ==, "The desktop rejected this request.");
}

void conversion_failure_does_not_launch() {
  int launches = 0;
  phonolite::DirectoryLauncher launcher([&](const std::string&) {
    ++launches;
    return phonolite::DirectoryOpenResult::accepted();
  });

  const auto result = launcher.open_directory("relative/library");

  g_assert_false(result.is_accepted());
  g_assert_false(result.message.empty());
  g_assert_cmpint(launches, ==, 0);
}

} // namespace

int main(int argc, char** argv) {
  g_test_init(&argc, &argv, nullptr);
  g_test_add_func("/directory-launcher/escaped-filename", converts_and_escapes_native_filename);
  g_test_add_func("/directory-launcher/native-failure", returns_native_launch_failure);
  g_test_add_func("/directory-launcher/conversion-failure", conversion_failure_does_not_launch);
  return g_test_run();
}
