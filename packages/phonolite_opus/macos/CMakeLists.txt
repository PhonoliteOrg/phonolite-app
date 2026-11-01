cmake_minimum_required(VERSION 3.16)
project(phonolite_opus_archive LANGUAGES C)

get_filename_component(OPUS_PACKAGE "${CMAKE_CURRENT_LIST_DIR}/.." REALPATH)
list(PREPEND CMAKE_MODULE_PATH "${OPUS_PACKAGE}/cmake")

set(OPUS_BUILD_SHARED_LIBRARY OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(OPUS_ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL_PKG_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL_CMAKE_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
set(CMAKE_SKIP_INSTALL_RULES ON)
add_subdirectory("${OPUS_PACKAGE}/third_party/opus" "${CMAKE_CURRENT_BINARY_DIR}/opus")

add_library(phonolite_opus STATIC "${OPUS_PACKAGE}/src/phonolite_opus.c")
target_include_directories(phonolite_opus PRIVATE "${OPUS_PACKAGE}/third_party/opus/include")
target_link_libraries(phonolite_opus PRIVATE opus)
set_target_properties(phonolite_opus opus PROPERTIES
  C_STANDARD 99
  POSITION_INDEPENDENT_CODE ON
  ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/lib"
  ARCHIVE_OUTPUT_DIRECTORY_RELEASE "${CMAKE_CURRENT_BINARY_DIR}/lib"
)
