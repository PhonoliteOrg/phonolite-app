#include "phonolite_audio.h"

#include "audio_output_devices.h"
#include "audio_queue_player.h"

#define PHONOLITE_EXPORT __attribute__((visibility("default"))) __attribute__((used))

PHONOLITE_EXPORT PhonoliteAudioPlayer *phonolite_audio_open(int32_t sample_rate, int32_t channels, int32_t device_id) {
  return audio_queue_player_open(sample_rate, channels, device_id);
}

PHONOLITE_EXPORT PhonoliteAudioPlayer *phonolite_audio_open_format(int32_t sample_rate, int32_t channels,
                                                                  int32_t device_id, int32_t bits_per_sample) {
  return audio_queue_player_open_format(sample_rate, channels, device_id, bits_per_sample);
}

PHONOLITE_EXPORT void phonolite_audio_close(PhonoliteAudioPlayer *player) {
  audio_queue_player_close(player);
}

PHONOLITE_EXPORT int32_t phonolite_audio_write(PhonoliteAudioPlayer *player, const int16_t *samples,
                                               int32_t sample_count) {
  return audio_queue_player_write(player, samples, sample_count);
}

PHONOLITE_EXPORT int32_t phonolite_audio_write32(PhonoliteAudioPlayer *player, const int32_t *samples,
                                                 int32_t sample_count) {
  return audio_queue_player_write32(player, samples, sample_count);
}

PHONOLITE_EXPORT void phonolite_audio_set_volume(PhonoliteAudioPlayer *player, float volume) {
  audio_queue_player_set_volume(player, volume);
}

PHONOLITE_EXPORT void phonolite_audio_pause(PhonoliteAudioPlayer *player) {
  audio_queue_player_pause(player);
}

PHONOLITE_EXPORT void phonolite_audio_resume(PhonoliteAudioPlayer *player) {
  audio_queue_player_resume(player);
}

PHONOLITE_EXPORT int32_t phonolite_audio_flush(PhonoliteAudioPlayer *player) {
  return audio_queue_player_flush(player);
}

PHONOLITE_EXPORT int64_t phonolite_audio_collect_done_samples(PhonoliteAudioPlayer *player) {
  return audio_queue_player_collect_done_samples(player);
}

PHONOLITE_EXPORT int32_t phonolite_audio_is_idle(PhonoliteAudioPlayer *player) {
  return audio_queue_player_is_idle(player);
}

PHONOLITE_EXPORT int32_t phonolite_audio_get_output_device_count(void) {
  return audio_output_devices_count();
}

PHONOLITE_EXPORT uint32_t phonolite_audio_get_output_device_id(int32_t index) {
  return audio_output_devices_id(index);
}

PHONOLITE_EXPORT int32_t phonolite_audio_get_output_device_name(uint32_t device_id, char *buffer,
                                                                int32_t buffer_length) {
  return audio_output_devices_name(device_id, buffer, buffer_length);
}
