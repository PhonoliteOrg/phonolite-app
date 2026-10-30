#ifndef PHONOLITE_LOCAL_AUDIO_H
#define PHONOLITE_LOCAL_AUDIO_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct LocalAudioHandle LocalAudioHandle;

LocalAudioHandle* phonolite_local_audio_open(const uint8_t* path, uint64_t path_len, int64_t start_ms);
LocalAudioHandle* phonolite_local_audio_open_remote(
    const uint8_t* url, uint64_t url_len,
    const uint8_t* token, uint64_t token_len,
    const uint8_t* server_pin, uint64_t server_pin_len,
    int64_t start_ms);
/* Source callbacks belong to the loaded QUIC library. open_quic consumes the
 * source handle, closing it on decoder close or any open failure. */
typedef int64_t (*PhonoliteSourceReadRange)(void*, uint64_t, uint8_t*, size_t, uint32_t, uint64_t*);
typedef int32_t (*PhonoliteSourceErrorCode)(void*);
typedef size_t (*PhonoliteSourceCopyError)(void*, uint8_t*, size_t);
typedef void (*PhonoliteSourceClose)(void*);
LocalAudioHandle* phonolite_local_audio_open_quic(
    void* source_handle,
    PhonoliteSourceReadRange read_range,
    PhonoliteSourceErrorCode error_code,
    PhonoliteSourceCopyError copy_error,
    PhonoliteSourceClose close,
    int64_t start_ms);
int64_t phonolite_local_audio_read(LocalAudioHandle* handle, int16_t* out, uint64_t max_samples);
/* Interleaved signed PCM32; integer source samples are left-aligned. */
int64_t phonolite_local_audio_read32(LocalAudioHandle* handle, int32_t* out, uint64_t max_samples);
int64_t phonolite_local_audio_seek(LocalAudioHandle* handle, int64_t position_ms);
int32_t phonolite_local_audio_sample_rate(LocalAudioHandle* handle);
int32_t phonolite_local_audio_bit_depth(LocalAudioHandle* handle);
/* HTTP status, -100 trust, -101 unsupported source, -102 invalid source,
 * or zero for a transient transport/read failure. Null reads the open error. */
int32_t phonolite_local_audio_error_code(LocalAudioHandle* handle);
int32_t phonolite_local_audio_channels(LocalAudioHandle* handle);
int64_t phonolite_local_audio_duration_ms(LocalAudioHandle* handle);
/* Playable PCM frames per channel after codec trimming; -1 if unknown. */
int64_t phonolite_local_audio_playable_frames(LocalAudioHandle* handle);
int64_t phonolite_local_audio_position_ms(LocalAudioHandle* handle);
uint64_t phonolite_local_audio_last_error(LocalAudioHandle* handle, uint8_t* out, uint64_t out_len);
void phonolite_local_audio_close(LocalAudioHandle* handle);

#ifdef __cplusplus
}
#endif

#endif
