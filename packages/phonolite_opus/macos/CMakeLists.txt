cmake_minimum_required(VERSION 3.16)
project(phonolite_opus_archive LANGUAGES C)

get_filename_component(OPUS_PACKAGE "${CMAKE_CURRENT_LIST_DIR}/.." REALPATH)
list(PREPEND CMAKE_MODULE_PATH "${OPUS_PACKAGE}/cmake")
include(OpusAppleArm64)

set(OPUS_BUILD_SHARED_LIBRARY OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(OPUS_ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL_PKG_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL_CMAKE_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
set(CMAKE_SKIP_INSTALL_RULES ON)
add_subdirectory("${OPUS_PACKAGE}/third_party/opus" "${CMAKE_CURRENT_BINARY_DIR}/opus")
phonolite_opus_enable_apple_arm64(opus)
set(CMAKE_SKIP_INSTALL_RULES OFF)

option(PHONOLITE_OPUS_SHARED "Build the macOS code asset as a dynamic library" OFF)
if(PHONOLITE_OPUS_SHARED)
  add_library(phonolite_opus SHARED "${OPUS_PACKAGE}/src/phonolite_opus.c")
else()
  add_library(phonolite_opus STATIC "${OPUS_PACKAGE}/src/phonolite_opus.c")
endif()
target_include_directories(phonolite_opus PRIVATE "${OPUS_PACKAGE}/third_party/opus/include")
target_link_libraries(phonolite_opus PRIVATE opus)
set_target_properties(phonolite_opus opus PROPERTIES
  C_STANDARD 99
  POSITION_INDEPENDENT_CODE ON
  ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/lib"
  ARCHIVE_OUTPUT_DIRECTORY_RELEASE "${CMAKE_CURRENT_BINARY_DIR}/lib"
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/lib"
  LIBRARY_OUTPUT_DIRECTORY_RELEASE "${CMAKE_CURRENT_BINARY_DIR}/lib"
)
