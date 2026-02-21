#ifndef PHONOLITE_QUIC_H
#define PHONOLITE_QUIC_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct QuicHandle QuicHandle;

QuicHandle* phonolite_quic_connect(const char* host, uint16_t port, const char* token);
int32_t phonolite_quic_open_track(
    QuicHandle* handle,
    const char* track_id,
    const char* mode,
    const char* quality,
    uint32_t frame_ms,
    const char* queue_json);
int32_t phonolite_quic_send_buffer(QuicHandle* handle, uint32_t buffer_ms, uint32_t target_ms);
int32_t phonolite_quic_send_playback(
    QuicHandle* handle,
    const char* track_id,
    uint32_t position_ms,
    int32_t playing);
int32_t phonolite_quic_advance(QuicHandle* handle);
int32_t phonolite_quic_read(QuicHandle* handle, uint8_t* buffer, uint64_t buffer_len);
char* phonolite_quic_last_error(QuicHandle* handle);
char* phonolite_quic_poll_stats(QuicHandle* handle);
void phonolite_quic_free_string(char* ptr);
void phonolite_quic_close(QuicHandle* handle);

#ifdef __cplusplus
}
#endif

#endif
