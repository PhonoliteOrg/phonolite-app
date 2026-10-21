#ifndef RUNNER_UI_SHELL_WIN32_WINDOW_H_
#define RUNNER_UI_SHELL_WIN32_WINDOW_H_

#include <string>

#include <windows.h>

#include "runner/data/models/window/window_geometry.h"

// Shared DPI-aware native frame. Subclasses specialize rendering and input.
class Win32Window {
 public:
  Win32Window();
  virtual ~Win32Window();

  Win32Window(const Win32Window&) = delete;
  Win32Window& operator=(const Win32Window&) = delete;
  Win32Window(Win32Window&&) = delete;
  Win32Window& operator=(Win32Window&&) = delete;

  HWND get_handle() const;
  RECT get_client_area() const;
  void set_quit_on_close(bool quit_on_close);

  // Logical coordinates and dimensions are scaled to physical pixels using
  // the nearest monitor's DPI. The window remains hidden until show().
  bool create(const std::wstring& title, const WindowPoint& origin, const WindowSize& size);
  bool show();
  void destroy();

  // Hosts a borrowed child HWND; its original owner retains its lifetime.
  void set_child_content(HWND content);

 protected:
  virtual bool on_create();
  virtual void on_destroy();
  virtual LRESULT message_handler(HWND window, UINT message, WPARAM wparam, LPARAM lparam) noexcept;

 private:
  friend class WindowClassRegistrar;

  bool quit_on_close_ = false;
  HWND window_handle_ = nullptr;
  HWND child_content_ = nullptr;

  // WM_NCCREATE establishes routing and enables non-client DPI scaling before
  // subsequent messages reach the instance's specialization hook.
  static LRESULT CALLBACK window_proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) noexcept;
  static Win32Window* get_this_from_handle(HWND window) noexcept;
  static void update_theme(HWND window);
};

#endif // RUNNER_UI_SHELL_WIN32_WINDOW_H_
