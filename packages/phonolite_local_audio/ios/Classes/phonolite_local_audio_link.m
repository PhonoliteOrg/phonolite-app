#import <Foundation/Foundation.h>
#include <stdint.h>

extern void *phonolite_local_audio_open(
    const uint8_t *path,
    uint64_t path_len,
    int64_t start_ms);
extern int64_t phonolite_local_audio_read(
    void *handle,
    int16_t *out,
    uint64_t max_samples);
extern int64_t phonolite_local_audio_seek(void *handle, int64_t position_ms);
extern int32_t phonolite_local_audio_sample_rate(void *handle);
extern int32_t phonolite_local_audio_channels(void *handle);
extern int64_t phonolite_local_audio_duration_ms(void *handle);
extern int64_t phonolite_local_audio_position_ms(void *handle);
extern uint64_t phonolite_local_audio_last_error(
    void *handle,
    uint8_t *out,
    uint64_t out_len);
extern void phonolite_local_audio_close(void *handle);

__attribute__((used)) static void *phonolite_local_audio_keep_symbols[] = {
  (void *)phonolite_local_audio_open,
  (void *)phonolite_local_audio_read,
  (void *)phonolite_local_audio_seek,
  (void *)phonolite_local_audio_sample_rate,
  (void *)phonolite_local_audio_channels,
  (void *)phonolite_local_audio_duration_ms,
  (void *)phonolite_local_audio_position_ms,
  (void *)phonolite_local_audio_last_error,
  (void *)phonolite_local_audio_close,
};
