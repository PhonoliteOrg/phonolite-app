cmake_minimum_required(VERSION 3.14)
project(phonolite_native_checks LANGUAGES CXX)

set(PHONOLITE_FLUTTER_ENGINE_DIR "" CACHE PATH "Cached Flutter windows-x64 engine directory")
if(NOT EXISTS "${PHONOLITE_FLUTTER_ENGINE_DIR}/flutter_windows.h")
  message(FATAL_ERROR "Set PHONOLITE_FLUTTER_ENGINE_DIR to the Flutter SDK's cached Windows engine directory")
endif()

get_filename_component(APP_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
set(WRAPPER_ROOT "${PHONOLITE_FLUTTER_ENGINE_DIR}/cpp_client_wrapper")
set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release" CACHE STRING "" FORCE)
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")

function(apply_native_check_settings target)
  target_compile_features(${target} PRIVATE cxx_std_17)
  target_compile_options(${target} PRIVATE /W4 /WX /wd4100 /EHsc)
  target_compile_definitions(${target} PRIVATE UNICODE _UNICODE NOMINMAX _HAS_EXCEPTIONS=0
    "$<$<CONFIG:Debug>:_DEBUG>")
  target_include_directories(${target} PRIVATE
    "${APP_ROOT}/windows"
    "${PHONOLITE_FLUTTER_ENGINE_DIR}"
    "${WRAPPER_ROOT}/include"
  )
endfunction()

# Compile the exact translation units registered by the production runner.
# This target does not link or launch the Flutter application.
file(READ "${APP_ROOT}/windows/runner/CMakeLists.txt" runner_build)
string(REGEX MATCH "add_executable\\([^)]*\\)" runner_definition "${runner_build}")
string(REGEX MATCHALL "\"[^\"]+\\.(cpp|cc)\"" registered_sources "${runner_definition}")
set(runner_sources)
foreach(source ${registered_sources})
  string(REPLACE "\"" "" source "${source}")
  string(REPLACE "\${FLUTTER_MANAGED_DIR}" "${APP_ROOT}/windows/flutter" source "${source}")
  if(NOT IS_ABSOLUTE "${source}")
    set(source "${APP_ROOT}/windows/runner/${source}")
  endif()
  list(APPEND runner_sources "${source}")
endforeach()
if(NOT runner_sources)
  message(FATAL_ERROR "No production runner sources were found")
endif()

add_library(phonolite_runner_compile OBJECT ${runner_sources})
apply_native_check_settings(phonolite_runner_compile)
file(GLOB plugin_includes LIST_DIRECTORIES true
  "${APP_ROOT}/windows/flutter/ephemeral/.plugin_symlinks/*/windows/include")
target_include_directories(phonolite_runner_compile PRIVATE ${plugin_includes})

add_executable(phonolite_native_contract_tests
  "native_contract_test.cpp"
  "${APP_ROOT}/windows/runner/infrastructure/flutter/directories_channel_adapter.cpp"
  "${APP_ROOT}/windows/runner/infrastructure/shell/directory_launcher.cpp"
  "${APP_ROOT}/windows/runner/infrastructure/text/text_encoding.cpp"
  "${WRAPPER_ROOT}/core_implementations.cc"
  "${WRAPPER_ROOT}/standard_codec.cc"
)
apply_native_check_settings(phonolite_native_contract_tests)
target_link_libraries(phonolite_native_contract_tests PRIVATE shell32.lib
  "${PHONOLITE_FLUTTER_ENGINE_DIR}/flutter_windows.dll.lib")
add_custom_command(TARGET phonolite_native_contract_tests POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${PHONOLITE_FLUTTER_ENGINE_DIR}/flutter_windows.dll"
    "$<TARGET_FILE_DIR:phonolite_native_contract_tests>"
  VERBATIM
)

enable_testing()
add_test(NAME phonolite_native_contracts COMMAND phonolite_native_contract_tests)
