#ifndef RUNNER_INFRASTRUCTURE_AUDIO_XAUDIO_OUTPUT_H_
#define RUNNER_INFRASTRUCTURE_AUDIO_XAUDIO_OUTPUT_H_

#include <stdint.h>

#if defined(PHONOLITE_AUDIO_WINDOWS_EXPORTS)
#define PHONOLITE_XAUDIO_API __declspec(dllexport)
#else
#define PHONOLITE_XAUDIO_API __declspec(dllimport)
#endif

#ifdef __cplusplus
extern "C" {
#endif

// One unopened Dart output owns one handle. Calls for a handle must be
// serialized, including close; native audio callbacks never call Dart.
// Device IDs retain the existing WinMM enumeration: -1 means System Default.
PHONOLITE_XAUDIO_API void* phonolite_xaudio_open(int32_t sample_rate, int32_t channels, int32_t device_id);
PHONOLITE_XAUDIO_API void* phonolite_xaudio_open_format(int32_t sample_rate, int32_t channels, int32_t device_id,
                                                        int32_t bits_per_sample, int32_t valid_bits_per_sample);
PHONOLITE_XAUDIO_API void phonolite_xaudio_close(void* output);

// Copies unscaled, interleaved PCM. Returns 0 when accepted, 1 for a full queue,
// or a negative HRESULT. The caller may release its samples after this returns.
PHONOLITE_XAUDIO_API int32_t phonolite_xaudio_write(void* output, const int16_t* samples, int32_t sample_count);
PHONOLITE_XAUDIO_API int32_t phonolite_xaudio_write32(void* output, const int32_t* samples, int32_t sample_count);
PHONOLITE_XAUDIO_API int32_t phonolite_xaudio_flush(void* output);
PHONOLITE_XAUDIO_API int32_t phonolite_xaudio_set_volume(void* output, float volume);
PHONOLITE_XAUDIO_API int32_t phonolite_xaudio_pause(void* output);
PHONOLITE_XAUDIO_API int32_t phonolite_xaudio_resume(void* output);

// Counts interleaved samples actually processed since the previous collection.
// Flush discards pending audio and starts a fresh counter. Errors are negative.
PHONOLITE_XAUDIO_API int64_t phonolite_xaudio_collect_done_samples(void* output);
PHONOLITE_XAUDIO_API int32_t phonolite_xaudio_is_idle(void* output);

#ifdef __cplusplus
}
#endif

#endif // RUNNER_INFRASTRUCTURE_AUDIO_XAUDIO_OUTPUT_H_
