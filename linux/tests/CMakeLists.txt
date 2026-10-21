cmake_minimum_required(VERSION 3.16)
project(phonolite_linux_checks LANGUAGES CXX)

enable_testing()

get_filename_component(LINUX_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)

function(configure_check TARGET)
  target_compile_features(${TARGET} PRIVATE cxx_std_14)
  set_target_properties(${TARGET} PROPERTIES CXX_EXTENSIONS OFF)
  target_include_directories(${TARGET} PRIVATE "${LINUX_SOURCE_DIR}")

  if(MSVC)
    target_compile_options(${TARGET} PRIVATE /W4 /WX)
  else()
    target_compile_options(${TARGET} PRIVATE -Wall -Wextra -Werror)
  endif()
endfunction()

add_executable(directory_open_result_test "directory_open_result_test.cc")
configure_check(directory_open_result_test)
add_test(NAME directory_open_result COMMAND directory_open_result_test)

set(PLATFORM_CHECKS_DEFAULT OFF)
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  set(PLATFORM_CHECKS_DEFAULT ON)
endif()

option(PHONOLITE_ENABLE_PLATFORM_CHECKS "Compile against the real GTK/GIO and Flutter Linux embedding" ${PLATFORM_CHECKS_DEFAULT})
if(NOT PHONOLITE_ENABLE_PLATFORM_CHECKS)
  return()
endif()

if(NOT CMAKE_SYSTEM_NAME STREQUAL "Linux")
  message(FATAL_ERROR "Platform checks require Linux; portable result checks do not need a platform SDK.")
endif()

find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)
pkg_check_modules(GIO REQUIRED IMPORTED_TARGET gio-2.0)

set(FLUTTER_EPHEMERAL_DIR "${LINUX_SOURCE_DIR}/flutter/ephemeral" CACHE PATH "Prepared Flutter Linux embedding directory")
find_path(FLUTTER_INCLUDE_DIR flutter_linux/flutter_linux.h PATHS "${FLUTTER_EPHEMERAL_DIR}" NO_DEFAULT_PATH)
find_library(FLUTTER_LIBRARY NAMES flutter_linux_gtk PATHS "${FLUTTER_EPHEMERAL_DIR}" NO_DEFAULT_PATH)
if(NOT FLUTTER_INCLUDE_DIR OR NOT FLUTTER_LIBRARY)
  message(FATAL_ERROR "Prepare the Flutter Linux embedding first, or set FLUTTER_EPHEMERAL_DIR to its SDK directory.")
endif()

# Compile the same registered sources as Runner, without linking or running an
# application. Plugin headers must already exist; no plugin build hooks run here.
set(FLUTTER_MANAGED_DIR "${LINUX_SOURCE_DIR}/flutter")
include("${LINUX_SOURCE_DIR}/runner/sources.cmake")
set(RUNNER_COMPILE_SOURCES)
foreach(SOURCE IN LISTS PHONOLITE_RUNNER_SOURCES)
  if(IS_ABSOLUTE "${SOURCE}")
    list(APPEND RUNNER_COMPILE_SOURCES "${SOURCE}")
  else()
    list(APPEND RUNNER_COMPILE_SOURCES "${LINUX_SOURCE_DIR}/runner/${SOURCE}")
  endif()
endforeach()

file(GLOB PLUGIN_INCLUDE_DIRS "${FLUTTER_EPHEMERAL_DIR}/.plugin_symlinks/*/linux/include")
add_library(linux_runner_compile OBJECT ${RUNNER_COMPILE_SOURCES})
configure_check(linux_runner_compile)
target_include_directories(linux_runner_compile PRIVATE "${FLUTTER_INCLUDE_DIR}" ${PLUGIN_INCLUDE_DIRS})
target_compile_definitions(linux_runner_compile PRIVATE APPLICATION_ID="com.example.phonolite_app")
target_link_libraries(linux_runner_compile PRIVATE PkgConfig::GTK PkgConfig::GIO)

add_library(directory_platform_sources OBJECT
  "${LINUX_SOURCE_DIR}/runner/infrastructure/flutter/directories_channel_adapter.cc"
  "${LINUX_SOURCE_DIR}/runner/infrastructure/shell/directory_launcher.cc"
)
configure_check(directory_platform_sources)
target_include_directories(directory_platform_sources PRIVATE "${FLUTTER_INCLUDE_DIR}")
target_link_libraries(directory_platform_sources PRIVATE PkgConfig::GTK PkgConfig::GIO)

add_executable(directory_launcher_test
  "directory_launcher_test.cc"
  "${LINUX_SOURCE_DIR}/runner/infrastructure/shell/directory_launcher.cc"
)
configure_check(directory_launcher_test)
target_link_libraries(directory_launcher_test PRIVATE PkgConfig::GIO)
add_test(NAME directory_launcher COMMAND directory_launcher_test)

add_executable(directories_channel_test
  "directories_channel_test.cc"
  "support/test_binary_messenger.cc"
  $<TARGET_OBJECTS:directory_platform_sources>
)
configure_check(directories_channel_test)
target_include_directories(directories_channel_test PRIVATE "${FLUTTER_INCLUDE_DIR}")
target_link_libraries(directories_channel_test PRIVATE "${FLUTTER_LIBRARY}" PkgConfig::GTK PkgConfig::GIO)
add_test(NAME directories_channel COMMAND directories_channel_test)
