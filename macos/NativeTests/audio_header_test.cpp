#include "phonolite_audio.h"

#include <type_traits>

// The public header must remain usable from C++ with the exact Dart FFI widths.
static_assert(
    std::is_same<decltype(&phonolite_audio_open), PhonoliteAudioPlayer *(*)(int32_t, int32_t, int32_t)>::value,
    "open ABI");
static_assert(std::is_same<decltype(&phonolite_audio_close), void (*)(PhonoliteAudioPlayer *)>::value, "close ABI");
static_assert(std::is_same<decltype(&phonolite_audio_write),
                           int32_t (*)(PhonoliteAudioPlayer *, const int16_t *, int32_t)>::value,
              "write ABI");
static_assert(std::is_same<decltype(&phonolite_audio_set_volume), void (*)(PhonoliteAudioPlayer *, float)>::value,
              "volume ABI");
static_assert(std::is_same<decltype(&phonolite_audio_pause), void (*)(PhonoliteAudioPlayer *)>::value, "pause ABI");
static_assert(std::is_same<decltype(&phonolite_audio_resume), void (*)(PhonoliteAudioPlayer *)>::value, "resume ABI");
static_assert(std::is_same<decltype(&phonolite_audio_flush), int32_t (*)(PhonoliteAudioPlayer *)>::value, "flush ABI");
static_assert(std::is_same<decltype(&phonolite_audio_collect_done_samples), int64_t (*)(PhonoliteAudioPlayer *)>::value,
              "completion ABI");
static_assert(std::is_same<decltype(&phonolite_audio_is_idle), int32_t (*)(PhonoliteAudioPlayer *)>::value, "idle ABI");
static_assert(std::is_same<decltype(&phonolite_audio_get_output_device_count), int32_t (*)(void)>::value, "count ABI");
static_assert(std::is_same<decltype(&phonolite_audio_get_output_device_id), uint32_t (*)(int32_t)>::value,
              "device ID ABI");
static_assert(
    std::is_same<decltype(&phonolite_audio_get_output_device_name), int32_t (*)(uint32_t, char *, int32_t)>::value,
    "device name ABI");
