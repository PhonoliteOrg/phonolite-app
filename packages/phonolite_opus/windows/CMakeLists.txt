cmake_minimum_required(VERSION 3.14)
project(phonolite_opus_library LANGUAGES C)

set(OPUS_ROOT "${CMAKE_CURRENT_LIST_DIR}/../third_party/opus")

set(OPUS_BUILD_SHARED_LIBRARY OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL_PKG_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL_CMAKE_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
set(OPUS_ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
set(CMAKE_INSTALL_PREFIX "${CMAKE_CURRENT_BINARY_DIR}/install" CACHE PATH "" FORCE)

set(CMAKE_SKIP_INSTALL_RULES ON)
add_subdirectory("${OPUS_ROOT}" "${CMAKE_CURRENT_BINARY_DIR}/opus")
set(CMAKE_SKIP_INSTALL_RULES OFF)

file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/opus/cmake_install.cmake"
  "if(NOT DEFINED CMAKE_INSTALL_PREFIX)\n"
  "  set(CMAKE_INSTALL_PREFIX \"\")\n"
  "endif()\n")

add_library(phonolite_opus SHARED
    "${CMAKE_CURRENT_LIST_DIR}/../src/phonolite_opus.c"
)

target_compile_definitions(phonolite_opus PRIVATE OPUS_BUILD HAVE_LRINTF HAVE_LRINT USE_ALLOCA)

target_include_directories(phonolite_opus PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/../src"
    "${OPUS_ROOT}/include"
    "${OPUS_ROOT}/celt"
    "${OPUS_ROOT}/silk"
    "${OPUS_ROOT}/silk/float"
)

target_link_libraries(phonolite_opus PRIVATE opus)

set(phonolite_opus_bundled_libraries
    $<TARGET_FILE:phonolite_opus>
    PARENT_SCOPE
)
