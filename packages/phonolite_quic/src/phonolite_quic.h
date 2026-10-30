#ifndef PHONOLITE_QUIC_H
#define PHONOLITE_QUIC_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct QuicHandle QuicHandle;

QuicHandle* phonolite_quic_connect(const char* host, uint16_t port, const char* token, const char* server_pin);
char* phonolite_security_login(const char* request_json);
char* phonolite_security_probe(const char* request_json);
char* phonolite_security_spki(const uint8_t* certificate, size_t length);
int32_t phonolite_quic_open_track(
    QuicHandle* handle,
    const char* track_id,
    const char* mode,
    const char* quality,
    uint32_t frame_ms,
    const char* queue_json);
int32_t phonolite_quic_open_track_at(
    QuicHandle* handle, const char* track_id, const char* mode,
    const char* quality, uint32_t frame_ms, const char* queue_json,
    uint32_t start_ms);
int32_t phonolite_quic_send_buffer(QuicHandle* handle, uint32_t buffer_ms, uint32_t target_ms);
int32_t phonolite_quic_send_playback(
    QuicHandle* handle,
    const char* track_id,
    uint32_t position_ms,
    int32_t playing);
int32_t phonolite_quic_seek(
    QuicHandle* handle,
    const char* track_id,
    uint32_t position_ms,
    uint32_t seek_id);
int32_t phonolite_quic_advance(QuicHandle* handle);
int32_t phonolite_quic_suspend_audio(QuicHandle* handle);
uint64_t phonolite_quic_generation(QuicHandle* handle);
int32_t phonolite_quic_read(QuicHandle* handle, uint8_t* buffer, size_t buffer_len);
char* phonolite_quic_poll_event(QuicHandle* handle);
char* phonolite_quic_last_error(QuicHandle* handle);
char* phonolite_quic_poll_stats(QuicHandle* handle);
long long phonolite_quic_poll_rtt_ms(QuicHandle* handle);
void phonolite_quic_free_string(char* ptr);
void phonolite_quic_close(QuicHandle* handle);
QuicHandle* phonolite_quic_connect_owned(const char* host, uint16_t port, const char* token, const char* expected_pin);
void phonolite_quic_heartbeat(QuicHandle* handle);
uint64_t phonolite_quic_owner_create(void);
void phonolite_quic_owner_heartbeat(uint64_t owner_id);
void phonolite_quic_owner_cancel(uint64_t owner_id);
int32_t phonolite_quic_owner_alive(uint64_t owner_id);
uint64_t phonolite_quic_owner_interrupt(uint64_t owner_id);
int32_t phonolite_quic_owner_begin_operation(uint64_t owner_id, uint64_t epoch);
void phonolite_quic_owner_release(void* owner_id);
void phonolite_quic_owner_release_finalizer(void* owner_id);
void* phonolite_quic_source_connect_owned(const char* host, uint16_t port, const char* track_id,
    const char* token, const char* server_pin, uint64_t owner_id);
void* phonolite_quic_source_connect(const char* host, uint16_t port, const char* track_id,
    const char* token, const char* server_pin);
int64_t phonolite_quic_source_read_range(void* handle, uint64_t offset, uint8_t* output,
    size_t capacity, uint32_t timeout_ms, uint64_t* total_length);
int32_t phonolite_quic_source_error_code(const void* handle);
size_t phonolite_quic_source_error(const void* handle, uint8_t* output, size_t capacity);
void phonolite_quic_source_close(void* handle);

#ifdef __cplusplus
}
#endif

#endif
