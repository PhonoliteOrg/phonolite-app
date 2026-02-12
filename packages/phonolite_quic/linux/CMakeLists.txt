cmake_minimum_required(VERSION 3.14)
project(phonolite_quic_library LANGUAGES C)

get_filename_component(RUST_ROOT "${CMAKE_CURRENT_LIST_DIR}/../native/quic_client" REALPATH)

if(CMAKE_BUILD_TYPE STREQUAL "Debug")
  set(CARGO_PROFILE "debug")
  set(CARGO_RELEASE_FLAG "")
else()
  set(CARGO_PROFILE "release")
  set(CARGO_RELEASE_FLAG "--release")
endif()

set(CARGO_TARGET_DIR "${CMAKE_CURRENT_BINARY_DIR}/cargo")
set(OUTPUT_SO "${CMAKE_CURRENT_BINARY_DIR}/libphonolite_quic.so")

add_custom_command(
  OUTPUT "${OUTPUT_SO}"
  COMMAND cargo build ${CARGO_RELEASE_FLAG} --target-dir "${CARGO_TARGET_DIR}"
  WORKING_DIRECTORY "${RUST_ROOT}"
  COMMAND ${CMAKE_COMMAND} -E copy
    "${CARGO_TARGET_DIR}/${CARGO_PROFILE}/libphonolite_quic.so"
    "${OUTPUT_SO}"
  COMMENT "Building phonolite_quic (Rust)"
)

add_custom_target(phonolite_quic_build ALL DEPENDS "${OUTPUT_SO}")

add_library(phonolite_quic SHARED IMPORTED GLOBAL)
set_target_properties(phonolite_quic PROPERTIES IMPORTED_LOCATION "${OUTPUT_SO}")
add_dependencies(phonolite_quic phonolite_quic_build)

set(phonolite_quic_bundled_libraries
  "${OUTPUT_SO}"
  PARENT_SCOPE
)
