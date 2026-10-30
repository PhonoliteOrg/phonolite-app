cmake_minimum_required(VERSION 3.16)
project(phonolite_local_opus LANGUAGES C)

# Share the app's checked-in libopus sources and its gitfile-aware version module.
get_filename_component(OPUS_PACKAGE "${CMAKE_CURRENT_LIST_DIR}/../../../../phonolite_opus" REALPATH)
list(PREPEND CMAKE_MODULE_PATH "${OPUS_PACKAGE}/cmake")
add_subdirectory("${OPUS_PACKAGE}/third_party/opus" "${CMAKE_CURRENT_BINARY_DIR}/opus")
