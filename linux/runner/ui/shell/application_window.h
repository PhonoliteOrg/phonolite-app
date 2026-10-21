#ifndef PHONOLITE_RUNNER_UI_SHELL_APPLICATION_WINDOW_H_
#define PHONOLITE_RUNNER_UI_SHELL_APPLICATION_WINDOW_H_

#include <gtk/gtk.h>

namespace phonolite {

// Shared GTK frame. GtkApplication owns the window; this wrapper borrows it.
class ApplicationWindow {
 public:
  explicit ApplicationWindow(GtkApplication* application);

  ApplicationWindow(const ApplicationWindow&) = delete;
  ApplicationWindow& operator=(const ApplicationWindow&) = delete;

  GtkWindow* window() const;

  void set_content(GtkWidget* content);
  void show();

 private:
  bool should_use_header_bar() const;
  void configure_title();
  void assemble();

  GtkWindow* window_;
};

} // namespace phonolite

#endif // PHONOLITE_RUNNER_UI_SHELL_APPLICATION_WINDOW_H_
