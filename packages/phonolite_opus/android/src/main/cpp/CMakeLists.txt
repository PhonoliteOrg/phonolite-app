cmake_minimum_required(VERSION 3.10)
project(phonolite_opus LANGUAGES C)

set(OPUS_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../../../third_party/opus")

set(OPUS_BUILD_SHARED_LIBRARY OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_TESTING OFF CACHE BOOL "" FORCE)

add_subdirectory("${OPUS_ROOT}" "${CMAKE_CURRENT_BINARY_DIR}/opus")

add_library(phonolite_opus SHARED
    "${CMAKE_CURRENT_LIST_DIR}/../../../../src/phonolite_opus.c"
)

target_compile_definitions(phonolite_opus PRIVATE OPUS_BUILD HAVE_LRINTF HAVE_LRINT USE_ALLOCA)

target_include_directories(phonolite_opus PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/../../../../src"
    "${OPUS_ROOT}/include"
    "${OPUS_ROOT}/celt"
    "${OPUS_ROOT}/silk"
    "${OPUS_ROOT}/silk/float"
)

target_link_libraries(phonolite_opus PRIVATE opus)
