#include "runner/bootstrap/flutter_host.h"

#include "flutter/generated_plugin_registrant.h"

namespace phonolite {
namespace {

constexpr char host_data_key[] = "phonolite-flutter-host";

} // namespace

FlutterHost::FlutterHost(GtkApplication* application)
    : window_(application), directories_(directory_launcher_),
      window_constraints_([this](int width, int height) { window_.set_minimum_content_size(width, height); }) {}

FlutterHost::~FlutterHost() {
  window_constraints_.detach();
  directories_.detach();

  if (first_frame_handler_ != 0) {
    g_signal_handler_disconnect(view_, first_frame_handler_);
  }

  if (view_destroy_handler_ != 0) {
    g_signal_handler_disconnect(view_, view_destroy_handler_);
  }

  if (window_destroy_handler_ != 0) {
    g_signal_handler_disconnect(window_.window(), window_destroy_handler_);
  }

  g_clear_object(&engine_);
}

void FlutterHost::create(GtkApplication* application, gchar** dart_entrypoint_arguments) noexcept {
  auto* host = new FlutterHost(application);
  GtkWindow* window = host->window_.window();
  g_object_set_data_full(G_OBJECT(window), host_data_key, host, release);

  // A normal destroy handler runs before GTK's default child destruction.
  host->window_destroy_handler_ = g_signal_connect(window, "destroy", G_CALLBACK(on_window_destroy), host);
  host->assemble(dart_entrypoint_arguments);
}

void FlutterHost::release(gpointer data) {
  delete static_cast<FlutterHost*>(data);
}

void FlutterHost::on_first_frame(FlView*, gpointer data) {
  auto* host = static_cast<FlutterHost*>(data);
  host->window_.show();
}

void FlutterHost::on_window_destroy(GtkWidget* window, gpointer) {
  // Clearing the association deletes the host; do not access it after this call.
  g_object_set_data(G_OBJECT(window), host_data_key, nullptr);
}

void FlutterHost::on_view_destroy(GtkWidget*, gpointer data) {
  auto* host = static_cast<FlutterHost*>(data);
  g_object_set_data(G_OBJECT(host->window_.window()), host_data_key, nullptr);
}

void FlutterHost::configure_icon() {
  // Resolve the relocatable Flutter bundle independently of the working directory.
  g_autofree gchar* executable = g_file_read_link("/proc/self/exe", nullptr);
  if (executable == nullptr) {
    return;
  }

  g_autofree gchar* directory = g_path_get_dirname(executable);
  g_autofree gchar* icon_path = g_build_filename(directory, "data", "flutter_assets", "assets", "images",
                                                 "phonolite-logo-nobackground.png", nullptr);
  g_autoptr(GdkPixbuf) icon = gdk_pixbuf_new_from_file(icon_path, nullptr);
  if (icon != nullptr) {
    window_.set_icon(icon);
  }
}

void FlutterHost::assemble(gchar** dart_entrypoint_arguments) {
  configure_icon();

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, dart_entrypoint_arguments);

  view_ = fl_view_new(project);
  engine_ = FL_ENGINE(g_object_ref(fl_view_get_engine(view_)));

  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view_, &background_color);
  gtk_widget_show(GTK_WIDGET(view_));
  window_.set_content(GTK_WIDGET(view_));

  first_frame_handler_ = g_signal_connect(view_, "first-frame", G_CALLBACK(on_first_frame), this);
  view_destroy_handler_ = g_signal_connect(view_, "destroy", G_CALLBACK(on_view_destroy), this);
  gtk_widget_realize(GTK_WIDGET(view_));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view_));
  directories_.attach(fl_engine_get_binary_messenger(engine_));
  window_constraints_.attach(fl_engine_get_binary_messenger(engine_));

  gtk_widget_grab_focus(GTK_WIDGET(view_));
}

} // namespace phonolite
