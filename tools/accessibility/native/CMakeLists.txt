cmake_minimum_required(VERSION 3.20)
project(native_ax_replay LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 20)
set(FLUTTER_ENGINE_ROOT "" CACHE PATH "Flutter SDK engine/src directory")
set(ax_root "${FLUTTER_ENGINE_ROOT}/flutter/third_party/accessibility")
if(NOT EXISTS "${ax_root}/ax/ax_tree.cc")
  message(FATAL_ERROR "Set FLUTTER_ENGINE_ROOT to your Flutter SDK's engine/src directory")
endif()

set(ax_sources
  ax_enum_util.cc ax_event_intent.cc ax_node.cc ax_node_data.cc
  ax_node_position.cc ax_node_text_styles.cc ax_relative_bounds.cc
  ax_role_properties.cc ax_table_info.cc ax_tree.cc ax_tree_data.cc
  ax_tree_id.cc ax_tree_id_registry.cc ax_tree_manager_map.cc ax_tree_observer.cc)
list(TRANSFORM ax_sources PREPEND "${ax_root}/ax/")
file(GLOB gfx_sources "${ax_root}/gfx/geometry/*.cc" "${ax_root}/gfx/range/*.cc")
list(FILTER gfx_sources EXCLUDE REGEX "test")

add_executable(native_ax_replay main.cpp string_utils_shim.cpp ${ax_sources} ${gfx_sources}
  "${ax_root}/gfx/transform.cc" "${ax_root}/base/logging.cc" "${ax_root}/base/simple_token.cc")
target_include_directories(native_ax_replay PRIVATE "${FLUTTER_ENGINE_ROOT}" "${ax_root}")
target_compile_definitions(native_ax_replay PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN
  _SILENCE_CXX17_CODECVT_HEADER_DEPRECATION_WARNING
  _SILENCE_CXX17_ITERATOR_BASE_CLASS_DEPRECATION_WARNING)
if(MSVC)
  target_compile_options(native_ax_replay PRIVATE /EHsc /bigobj)
endif()
