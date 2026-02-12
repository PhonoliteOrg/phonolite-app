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
set(OUTPUT_DLL "${CMAKE_CURRENT_BINARY_DIR}/phonolite_quic.dll")

add_custom_command(
  OUTPUT "${OUTPUT_DLL}"
  COMMAND cargo build ${CARGO_RELEASE_FLAG} --target-dir "${CARGO_TARGET_DIR}"
  WORKING_DIRECTORY "${RUST_ROOT}"
  COMMAND ${CMAKE_COMMAND} -E copy
    "${CARGO_TARGET_DIR}/${CARGO_PROFILE}/phonolite_quic.dll"
    "${OUTPUT_DLL}"
  COMMENT "Building phonolite_quic (Rust)"
)

add_custom_target(phonolite_quic_build ALL DEPENDS "${OUTPUT_DLL}")

add_library(phonolite_quic SHARED IMPORTED GLOBAL)
set_target_properties(phonolite_quic PROPERTIES IMPORTED_LOCATION "${OUTPUT_DLL}")
add_dependencies(phonolite_quic phonolite_quic_build)

set(phonolite_quic_bundled_libraries
  "${OUTPUT_DLL}"
  PARENT_SCOPE
)
