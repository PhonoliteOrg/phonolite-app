#ifndef PHONOLITE_RUNNER_BOOTSTRAP_FLUTTER_HOST_H_
#define PHONOLITE_RUNNER_BOOTSTRAP_FLUTTER_HOST_H_

#include <flutter_linux/flutter_linux.h>

#include "runner/infrastructure/flutter/directories_channel_adapter.h"
#include "runner/infrastructure/shell/directory_launcher.h"
#include "runner/ui/shell/application_window.h"

namespace phonolite {

// Main-context composition for one window and engine. GTK destruction releases it.
class FlutterHost {
 public:
  static void create(GtkApplication* application, gchar** dart_entrypoint_arguments) noexcept;

 private:
  explicit FlutterHost(GtkApplication* application);
  ~FlutterHost();

  FlutterHost(const FlutterHost&) = delete;
  FlutterHost& operator=(const FlutterHost&) = delete;

  static void release(gpointer data);
  static void on_first_frame(FlView* view, gpointer data);
  static void on_window_destroy(GtkWidget* window, gpointer data);
  static void on_view_destroy(GtkWidget* view, gpointer data);

  void configure_icon();
  void assemble(gchar** dart_entrypoint_arguments);

  ApplicationWindow window_;
  DirectoryLauncher directory_launcher_;
  DirectoriesChannelAdapter directories_;

  FlView* view_ = nullptr;     // Borrowed from the window's container.
  FlEngine* engine_ = nullptr; // Owned until handlers are detached, even during view disposal.
  gulong first_frame_handler_ = 0;
  gulong window_destroy_handler_ = 0;
  gulong view_destroy_handler_ = 0;
};

} // namespace phonolite

#endif // PHONOLITE_RUNNER_BOOTSTRAP_FLUTTER_HOST_H_
