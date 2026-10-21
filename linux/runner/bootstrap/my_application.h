#ifndef PHONOLITE_RUNNER_BOOTSTRAP_MY_APPLICATION_H_
#define PHONOLITE_RUNNER_BOOTSTRAP_MY_APPLICATION_H_

#include <gtk/gtk.h>

G_DECLARE_FINAL_TYPE(MyApplication, my_application, MY, APPLICATION, GtkApplication)

// Returns an owned application reference; GApplication runs the process lifecycle.
MyApplication* my_application_new();

#endif // PHONOLITE_RUNNER_BOOTSTRAP_MY_APPLICATION_H_
