#include "runner/bootstrap/my_application.h"

#include "runner/infrastructure/shell/update_launch_guard.h"

int main(int argc, char** argv) {
  if (!phonolite::update_allows_launch()) {
    g_printerr("A Phonolite update is in progress. Wait for the updater to finish.\n");
    return 75;
  }
  g_autoptr(MyApplication) app = my_application_new();

  return g_application_run(G_APPLICATION(app), argc, argv);
}
