#ifndef PHONOLITE_AUDIO_H
#define PHONOLITE_AUDIO_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque AudioQueue resource. Serialize control/write calls; callbacks are independent.
typedef struct PhonoliteAudioPlayer PhonoliteAudioPlayer;

PhonoliteAudioPlayer *phonolite_audio_open(int32_t sample_rate, int32_t channels, int32_t device_id);
void phonolite_audio_close(PhonoliteAudioPlayer *player);

// Counts refer to interleaved Int16 samples, not frames or bytes.
int32_t phonolite_audio_write(PhonoliteAudioPlayer *player, const int16_t *samples, int32_t sample_count);
void phonolite_audio_set_volume(PhonoliteAudioPlayer *player, float volume);
void phonolite_audio_pause(PhonoliteAudioPlayer *player);
void phonolite_audio_resume(PhonoliteAudioPlayer *player);
int32_t phonolite_audio_flush(PhonoliteAudioPlayer *player);
int64_t phonolite_audio_collect_done_samples(PhonoliteAudioPlayer *player);
int32_t phonolite_audio_is_idle(PhonoliteAudioPlayer *player);

int32_t phonolite_audio_get_output_device_count(void);
uint32_t phonolite_audio_get_output_device_id(int32_t index);

// The caller owns the UTF-8 name buffer, including its terminating null byte.
int32_t phonolite_audio_get_output_device_name(uint32_t device_id, char *buffer, int32_t buffer_length);

#ifdef __cplusplus
}
#endif

#endif
