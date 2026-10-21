#include "runner/ui/shell/win32_window.h"

#include <dwmapi.h>

#include <flutter_windows.h>

#include "runner/resource.h"

namespace {

// Support SDK versions predating the named dark-mode window attribute.
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr const wchar_t window_class_name[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr const wchar_t preferred_brightness_registry_key[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t preferred_brightness_registry_value[] = L"AppsUseLightTheme";

int active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND window);

int scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

void enable_full_dpi_support_if_available(HWND window) {
  HMODULE user32_module = LoadLibraryA("User32.dll");

  if (!user32_module) {
    return;
  }

  const auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(GetProcAddress(user32_module, "EnableNonClientDpiScaling"));

  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(window);
  }

  FreeLibrary(user32_module);
}

} // namespace

// Registration shares the frame family's lifetime and message-routing contract.
class WindowClassRegistrar final {
 public:
  ~WindowClassRegistrar() = default;

  static WindowClassRegistrar* get_instance();
  const wchar_t* get_window_class();
  void unregister_window_class();

 private:
  static WindowClassRegistrar* instance_;
  bool class_registered_ = false;

  WindowClassRegistrar() = default;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

WindowClassRegistrar* WindowClassRegistrar::get_instance() {
  if (!instance_) {
    instance_ = new WindowClassRegistrar();
  }

  return instance_;
}

const wchar_t* WindowClassRegistrar::get_window_class() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = window_class_name;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon = LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::window_proc;

    RegisterClass(&window_class);
    class_registered_ = true;
  }

  return window_class_name;
}

void WindowClassRegistrar::unregister_window_class() {
  UnregisterClass(window_class_name, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++active_window_count;
}

Win32Window::~Win32Window() {
  --active_window_count;
  destroy();
}

bool Win32Window::create(const std::wstring& title, const WindowPoint& origin, const WindowSize& size) {
  destroy();

  const wchar_t* window_class = WindowClassRegistrar::get_instance()->get_window_class();
  const POINT target_point = {static_cast<LONG>(origin.x), static_cast<LONG>(origin.y)};
  const HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  const UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  const double scale_factor = dpi / 96.0;

  HWND window = CreateWindow(window_class, title.c_str(), WS_OVERLAPPEDWINDOW, scale(origin.x, scale_factor),
                             scale(origin.y, scale_factor), scale(size.width, scale_factor),
                             scale(size.height, scale_factor), nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  update_theme(window);

  return on_create();
}

bool Win32Window::show() {
  return ShowWindow(window_handle_, SW_SHOWNORMAL);
}

void Win32Window::destroy() {
  on_destroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }

  if (active_window_count == 0) {
    WindowClassRegistrar::get_instance()->unregister_window_class();
  }
}

HWND Win32Window::get_handle() const {
  return window_handle_;
}

RECT Win32Window::get_client_area() const {
  RECT frame;
  GetClientRect(window_handle_, &frame);

  return frame;
}

void Win32Window::set_quit_on_close(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

void Win32Window::set_child_content(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);

  const RECT frame = get_client_area();
  MoveWindow(content, frame.left, frame.top, frame.right - frame.left, frame.bottom - frame.top, true);
  SetFocus(child_content_);
}

bool Win32Window::on_create() {
  return true;
}

void Win32Window::on_destroy() {}

LRESULT Win32Window::message_handler(HWND window, UINT message, WPARAM wparam, LPARAM lparam) noexcept {
  switch (message) {
  case WM_DESTROY:
    window_handle_ = nullptr;
    destroy();

    if (quit_on_close_) {
      PostQuitMessage(0);
    }

    return 0;

  case WM_DPICHANGED: {
    const auto new_rect = reinterpret_cast<RECT*>(lparam);
    const LONG new_width = new_rect->right - new_rect->left;
    const LONG new_height = new_rect->bottom - new_rect->top;

    SetWindowPos(window, nullptr, new_rect->left, new_rect->top, new_width, new_height, SWP_NOZORDER | SWP_NOACTIVATE);

    return 0;
  }

  case WM_SIZE: {
    const RECT rect = get_client_area();

    if (child_content_ != nullptr) {
      MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top, TRUE);
    }

    return 0;
  }

  case WM_ACTIVATE:
    if (child_content_ != nullptr) {
      SetFocus(child_content_);
    }

    return 0;

  case WM_DWMCOLORIZATIONCOLORCHANGED:
    update_theme(window);

    return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

LRESULT CALLBACK Win32Window::window_proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) noexcept {
  if (message == WM_NCCREATE) {
    const auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    const auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    enable_full_dpi_support_if_available(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = get_this_from_handle(window)) {
    return that->message_handler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

Win32Window* Win32Window::get_this_from_handle(HWND window) noexcept {
  return reinterpret_cast<Win32Window*>(GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::update_theme(HWND window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  const LSTATUS result =
      RegGetValue(HKEY_CURRENT_USER, preferred_brightness_registry_key, preferred_brightness_registry_value,
                  RRF_RT_REG_DWORD, nullptr, &light_mode, &light_mode_size);

  if (result == ERROR_SUCCESS) {
    const BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE, &enable_dark_mode, sizeof(enable_dark_mode));
  }
}
