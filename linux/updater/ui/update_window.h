#ifndef PHONOLITE_UPDATER_UI_UPDATE_WINDOW_H_
#define PHONOLITE_UPDATER_UI_UPDATE_WINDOW_H_

#include <string>

#include <gtk/gtk.h>

namespace phonolite {
namespace updates {

class UpdateWindow {
 public:
  UpdateWindow();
  ~UpdateWindow();
  void present();
  void update(const std::string& message, bool finished = false);
  void run();

 private:
  GtkWidget* window_ = nullptr;
  GtkWidget* label_ = nullptr;
  GtkWidget* close_ = nullptr;
  bool finished_ = false;
};

} // namespace updates
} // namespace phonolite
#endif
