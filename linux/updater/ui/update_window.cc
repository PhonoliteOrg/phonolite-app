#include "ui/update_window.h"

#include <memory>
#include <stdexcept>

namespace phonolite {
namespace updates {

UpdateWindow::UpdateWindow() {
  if (!gtk_init_check(nullptr, nullptr)) {
    throw std::runtime_error("Open the updater from a desktop session with an authentication agent.");
  }
  window_ = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  g_object_ref_sink(window_);
  gtk_window_set_title(GTK_WINDOW(window_), "Phonolite updater");
  gtk_window_set_default_size(GTK_WINDOW(window_), 460, 180);
  gtk_window_set_position(GTK_WINDOW(window_), GTK_WIN_POS_CENTER);
  GtkWidget* layout = gtk_box_new(GTK_ORIENTATION_VERTICAL, 18);
  gtk_container_set_border_width(GTK_CONTAINER(layout), 24);
  label_ = gtk_label_new("Waiting for administrator authorization…");
  gtk_label_set_line_wrap(GTK_LABEL(label_), TRUE);
  gtk_label_set_max_width_chars(GTK_LABEL(label_), 60);
  close_ = gtk_button_new_with_label("Close");
  gtk_widget_set_sensitive(close_, FALSE);
  gtk_box_pack_start(GTK_BOX(layout), label_, TRUE, TRUE, 0);
  gtk_box_pack_end(GTK_BOX(layout), close_, FALSE, FALSE, 0);
  gtk_container_add(GTK_CONTAINER(window_), layout);
  g_signal_connect(close_, "clicked", G_CALLBACK(+[](GtkButton*, gpointer data) {
                     gtk_widget_destroy(static_cast<UpdateWindow*>(data)->window_);
                   }),
                   this);
  g_signal_connect(window_, "delete-event", G_CALLBACK(+[](GtkWidget*, GdkEvent*, gpointer data) -> gboolean {
                     return !static_cast<UpdateWindow*>(data)->finished_;
                   }),
                   this);
  g_signal_connect(window_, "destroy", G_CALLBACK(+[](GtkWidget*, gpointer) { gtk_main_quit(); }), nullptr);
}

UpdateWindow::~UpdateWindow() {
  g_clear_object(&window_);
}

void UpdateWindow::present() {
  gtk_widget_show_all(window_);
}

void UpdateWindow::update(const std::string& message, bool finished) {
  struct Pending {
    UpdateWindow* window;
    std::string message;
    bool finished;
  };
  auto* pending = new Pending{this, message, finished};
  g_idle_add_full(
      G_PRIORITY_DEFAULT,
      +[](gpointer data) -> gboolean {
        auto* pending = static_cast<Pending*>(data);
        auto* window = pending->window;
        gtk_label_set_text(GTK_LABEL(window->label_), pending->message.c_str());
        window->finished_ = pending->finished;
        gtk_widget_set_sensitive(window->close_, window->finished_);
        return G_SOURCE_REMOVE;
      },
      pending, +[](gpointer data) { delete static_cast<Pending*>(data); });
}

void UpdateWindow::run() {
  gtk_main();
}

} // namespace updates
} // namespace phonolite
