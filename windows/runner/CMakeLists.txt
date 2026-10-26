cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "main.cpp"
  "data/configuration/app_identity.h.in"
  "data/configuration/updates.h.in"
  "bootstrap/flutter_window.cpp"
  "bootstrap/flutter_window.h"
  "data/models/directories/directory_open_result.h"
  "data/models/media/now_playing_snapshot.h"
  "data/models/window/window_geometry.h"
  "infrastructure/flutter/directories_channel_adapter.cpp"
  "infrastructure/flutter/directories_channel_adapter.h"
  "infrastructure/flutter/now_playing_channel_adapter.cpp"
  "infrastructure/flutter/now_playing_channel_adapter.h"
  "infrastructure/flutter/now_playing_codec.cpp"
  "infrastructure/flutter/now_playing_codec.h"
  "infrastructure/flutter/updates_channel_adapter.cpp"
  "infrastructure/flutter/updates_channel_adapter.h"
  "infrastructure/updates/update_service.h"
  "infrastructure/updates/windows_update_service.cpp"
  "infrastructure/updates/windows_update_service.h"
  "infrastructure/media/media_command_queue.h"
  "infrastructure/media/media_transport.h"
  "infrastructure/media/windows_media_transport.cpp"
  "infrastructure/media/windows_media_transport.h"
  "infrastructure/process/command_line.cpp"
  "infrastructure/process/command_line.h"
  "infrastructure/process/console_support.cpp"
  "infrastructure/process/console_support.h"
  "infrastructure/shell/directory_launcher.cpp"
  "infrastructure/shell/directory_launcher.h"
  "infrastructure/shell/application_identity.cpp"
  "infrastructure/shell/application_identity.h"
  "infrastructure/text/text_encoding.cpp"
  "infrastructure/text/text_encoding.h"
  "ui/shell/win32_window.cpp"
  "ui/shell/win32_window.h"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})
include("${CMAKE_CURRENT_SOURCE_DIR}/identity.cmake")
configure_phonolite_identity(${BINARY_NAME})
include("${CMAKE_CURRENT_SOURCE_DIR}/updates.cmake")
configure_phonolite_updates(${BINARY_NAME})
set(PHONOLITE_WINSPARKLE_SDK "${PHONOLITE_WINSPARKLE_SDK}" PARENT_SCOPE)

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib" "shell32.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "windowsapp.lib" "runtimeobject.lib" "shcore.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "propsys.lib" "advapi32.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
