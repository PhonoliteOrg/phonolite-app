#include "runner/ui/shell/application_window.h"

#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

namespace phonolite {
namespace {

constexpr int default_window_width = 1280;
constexpr int default_window_height = 720;

} // namespace

ApplicationWindow::ApplicationWindow(GtkApplication* application)
    : window_(GTK_WINDOW(gtk_application_window_new(application))) {
  assemble();
}

GtkWindow* ApplicationWindow::window() const {
  return window_;
}

void ApplicationWindow::set_icon(GdkPixbuf* icon) {
  gtk_window_set_icon(window_, icon);
}

void ApplicationWindow::set_content(GtkWidget* content) {
  gtk_container_add(GTK_CONTAINER(window_), content);
}

void ApplicationWindow::set_minimum_content_size(int width, int height) {
  GtkWidget* content = gtk_bin_get_child(GTK_BIN(window_));
  g_return_if_fail(content != nullptr);

  // GTK adds its own title bar and shadows around this borrowed content widget.
  gtk_widget_set_size_request(content, width, height);
}

void ApplicationWindow::show() {
  gtk_widget_show(GTK_WIDGET(window_));
}

bool ApplicationWindow::should_use_header_bar() const {
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window_);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* window_manager = gdk_x11_screen_get_window_manager_name(screen);

    return g_strcmp0(window_manager, "GNOME Shell") == 0;
  }
#endif

  return true;
}

void ApplicationWindow::configure_title() {
  const gchar* title = g_get_application_name();
  gtk_window_set_title(window_, title);

  if (!should_use_header_bar()) {
    return;
  }

  GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
  gtk_widget_show(GTK_WIDGET(header_bar));
  gtk_header_bar_set_title(header_bar, title);
  gtk_header_bar_set_show_close_button(header_bar, TRUE);
  gtk_window_set_titlebar(window_, GTK_WIDGET(header_bar));
}

void ApplicationWindow::assemble() {
  configure_title();
  gtk_window_set_default_size(window_, default_window_width, default_window_height);
}

} // namespace phonolite
