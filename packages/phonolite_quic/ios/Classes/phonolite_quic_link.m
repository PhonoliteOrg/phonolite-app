#import <Foundation/Foundation.h>
#include <stdint.h>

extern void *phonolite_quic_connect(const char *host, uint16_t port, const char *token, const char *server_pin);
extern char *phonolite_security_login(const char *request_json);
extern char *phonolite_security_probe(const char *request_json);
extern char *phonolite_security_spki(const uint8_t *certificate, size_t length);
extern int32_t phonolite_quic_open_track(
    void *handle,
    const char *track_id,
    const char *mode,
    const char *quality,
    uint32_t frame_ms,
    const char *queue_json);
extern int32_t phonolite_quic_open_track_at(
    void *handle, const char *track_id, const char *mode, const char *quality,
    uint32_t frame_ms, const char *queue_json, uint32_t start_ms);
extern int32_t phonolite_quic_suspend_audio(void *handle);
extern uint64_t phonolite_quic_generation(void *handle);
extern char *phonolite_quic_poll_event(void *handle);
extern int32_t phonolite_quic_send_buffer(void *handle, uint32_t buffer_ms, uint32_t target_ms);
extern int32_t phonolite_quic_send_playback(
    void *handle,
    const char *track_id,
    uint32_t position_ms,
    int32_t playing);
extern int32_t phonolite_quic_seek(
    void *handle,
    const char *track_id,
    uint32_t position_ms,
    uint32_t seek_id);
extern int32_t phonolite_quic_advance(void *handle);
extern int32_t phonolite_quic_read(void *handle, uint8_t *buffer, size_t buffer_len);
extern char *phonolite_quic_last_error(void *handle);
extern char *phonolite_quic_poll_stats(void *handle);
extern long long phonolite_quic_poll_rtt_ms(void *handle);
extern void phonolite_quic_free_string(char *ptr);
extern void phonolite_quic_close(void *handle);
extern void *phonolite_quic_connect_owned(const char *, uint16_t, const char *, const char *);
extern void phonolite_quic_heartbeat(void *);
extern uint64_t phonolite_quic_owner_create(void);
extern void phonolite_quic_owner_heartbeat(uint64_t);
extern void phonolite_quic_owner_cancel(uint64_t);
extern int32_t phonolite_quic_owner_alive(uint64_t);
extern uint64_t phonolite_quic_owner_interrupt(uint64_t);
extern int32_t phonolite_quic_owner_begin_operation(uint64_t, uint64_t);
extern void phonolite_quic_owner_release(void *);
extern void phonolite_quic_owner_release_finalizer(void *);
extern void *phonolite_quic_source_connect_owned(const char *, uint16_t, const char *, const char *, const char *, uint64_t);
extern void *phonolite_quic_source_connect(const char *, uint16_t, const char *, const char *, const char *);
extern int64_t phonolite_quic_source_read_range(void *, uint64_t, uint8_t *, size_t, uint32_t, uint64_t *);
extern int32_t phonolite_quic_source_error_code(const void *);
extern size_t phonolite_quic_source_error(const void *, uint8_t *, size_t);
extern void phonolite_quic_source_close(void *);

__attribute__((used)) static void *phonolite_quic_keep_symbols[] = {
  (void *)phonolite_security_login,
  (void *)phonolite_security_probe,
  (void *)phonolite_security_spki,
  (void *)phonolite_quic_connect,
  (void *)phonolite_quic_open_track,
  (void *)phonolite_quic_open_track_at,
  (void *)phonolite_quic_suspend_audio,
  (void *)phonolite_quic_generation,
  (void *)phonolite_quic_poll_event,
  (void *)phonolite_quic_send_buffer,
  (void *)phonolite_quic_send_playback,
  (void *)phonolite_quic_seek,
  (void *)phonolite_quic_advance,
  (void *)phonolite_quic_read,
  (void *)phonolite_quic_last_error,
  (void *)phonolite_quic_poll_stats,
  (void *)phonolite_quic_poll_rtt_ms,
  (void *)phonolite_quic_free_string,
  (void *)phonolite_quic_close,
  (void *)phonolite_quic_connect_owned,
  (void *)phonolite_quic_heartbeat,
  (void *)phonolite_quic_owner_create,
  (void *)phonolite_quic_owner_heartbeat,
  (void *)phonolite_quic_owner_cancel,
  (void *)phonolite_quic_owner_alive,
  (void *)phonolite_quic_owner_interrupt,
  (void *)phonolite_quic_owner_begin_operation,
  (void *)phonolite_quic_owner_release,
  (void *)phonolite_quic_owner_release_finalizer,
  (void *)phonolite_quic_source_connect_owned,
  (void *)phonolite_quic_source_connect,
  (void *)phonolite_quic_source_read_range,
  (void *)phonolite_quic_source_error_code,
  (void *)phonolite_quic_source_error,
  (void *)phonolite_quic_source_close,
};
