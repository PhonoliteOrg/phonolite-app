cmake_minimum_required(VERSION 3.19)
project(phonolite_updater LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
# Installed privileged helpers resolve only native system runtime libraries.
set(CMAKE_SKIP_RPATH TRUE)
find_package(PkgConfig REQUIRED)
pkg_check_modules(JSON REQUIRED IMPORTED_TARGET json-glib-1.0>=1.6)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)
find_package(OpenSSL 1.1.1 REQUIRED COMPONENTS Crypto)
find_package(Threads REQUIRED)
find_package(Python3 REQUIRED COMPONENTS Interpreter)
set(PHONOLITE_UPDATE_CONFIGURATION "${CMAKE_CURRENT_SOURCE_DIR}/../../distribution_tools/linux/config.json" CACHE FILEPATH "Public updater configuration")
execute_process(
  COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/../../distribution_tools/linux/generate_native_config.py"
          "${PHONOLITE_UPDATE_CONFIGURATION}" "${CMAKE_CURRENT_BINARY_DIR}/generated_configuration.h"
  COMMAND_ERROR_IS_FATAL ANY
)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${PHONOLITE_UPDATE_CONFIGURATION}")
add_library(phonolite_update_core STATIC
  data/models/update_types.h
  data/models/update_types.cc
  infrastructure/update_json.h
  infrastructure/update_json.cc
  infrastructure/manifest_verifier.h
  infrastructure/manifest_verifier.cc
  infrastructure/system_operations.h
  infrastructure/system_operations.cc
  infrastructure/package_manager.h
  infrastructure/package_manager.cc
  infrastructure/update_configuration.h
  infrastructure/update_configuration.cc
  infrastructure/update_request.h
  infrastructure/update_request.cc
  infrastructure/update_receipt.h
  infrastructure/update_receipt.cc
)
target_include_directories(phonolite_update_core PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}" "${CMAKE_CURRENT_BINARY_DIR}")
target_link_libraries(phonolite_update_core PUBLIC PkgConfig::JSON OpenSSL::Crypto Threads::Threads)
target_compile_options(phonolite_update_core PRIVATE -Wall -Wextra -Werror)
add_executable(phonolite-update-installer bootstrap/installer_main.cc application/installation_workflow.h application/installation_workflow.cc)
target_link_libraries(phonolite-update-installer PRIVATE phonolite_update_core)
add_executable(phonolite-update-coordinator bootstrap/coordinator_main.cc application/coordinator_workflow.h application/coordinator_workflow.cc ui/update_window.h ui/update_window.cc)
target_link_libraries(phonolite-update-coordinator PRIVATE phonolite_update_core PkgConfig::GTK)
foreach(target phonolite-update-installer phonolite-update-coordinator)
  target_compile_options(${target} PRIVATE -Wall -Wextra -Werror)
endforeach()
include(CTest)
if(BUILD_TESTING)
  add_executable(phonolite-updater-tests tests/updater_test.cc)
  target_link_libraries(phonolite-updater-tests PRIVATE phonolite_update_core)
  target_compile_options(phonolite-updater-tests PRIVATE -Wall -Wextra -Werror)
  add_test(NAME updater_contracts COMMAND phonolite-updater-tests)
endif()
