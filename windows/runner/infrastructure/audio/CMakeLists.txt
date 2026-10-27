cmake_minimum_required(VERSION 3.14)

# Also supports compiling the actual DLL alone, without building or starting
# Flutter and without opening an audio device.
if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
  project(phonolite_audio_windows LANGUAGES CXX)
endif()

add_library(phonolite_audio_windows SHARED
  "xaudio_output.cpp"
  "xaudio_output.h"
)

function(configure_phonolite_audio_target target)
  target_compile_features(${target} PRIVATE cxx_std_17)
  target_compile_options(${target} PRIVATE /W4 /WX /EHsc)
  target_compile_definitions(${target} PRIVATE
    PHONOLITE_AUDIO_WINDOWS_EXPORTS UNICODE _UNICODE NOMINMAX WIN32_LEAN_AND_MEAN
  )
  target_link_libraries(${target} PRIVATE xaudio2.lib ole32.lib winmm.lib)
endfunction()

configure_phonolite_audio_target(phonolite_audio_windows)

if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
  enable_testing()
  add_executable(phonolite_xaudio_contract_tests "../../../tests/xaudio_output_test.cpp")
  configure_phonolite_audio_target(phonolite_xaudio_contract_tests)
  add_test(NAME phonolite_xaudio_contracts COMMAND phonolite_xaudio_contract_tests)
endif()
