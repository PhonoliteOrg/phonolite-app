#ifndef AUDIO_QUEUE_PLAYER_H
#define AUDIO_QUEUE_PLAYER_H

#include "phonolite_audio.h"

// Implementation contract for the opaque public handle; resources remain private.
// The Dart owner serializes controls/writes. AudioQueue completions run independently.
#define PHONOLITE_QUEUE_INTERNAL __attribute__((visibility("hidden")))

PHONOLITE_QUEUE_INTERNAL PhonoliteAudioPlayer *audio_queue_player_open(int32_t sample_rate, int32_t channels,
                                                                       int32_t device_id);
PHONOLITE_QUEUE_INTERNAL PhonoliteAudioPlayer *audio_queue_player_open_format(int32_t sample_rate, int32_t channels,
                                                                              int32_t device_id, int32_t bits_per_sample);
PHONOLITE_QUEUE_INTERNAL void audio_queue_player_close(PhonoliteAudioPlayer *player);

PHONOLITE_QUEUE_INTERNAL int32_t audio_queue_player_write(PhonoliteAudioPlayer *player, const int16_t *samples,
                                                          int32_t sample_count);
PHONOLITE_QUEUE_INTERNAL int32_t audio_queue_player_write32(PhonoliteAudioPlayer *player, const int32_t *samples,
                                                            int32_t sample_count);
PHONOLITE_QUEUE_INTERNAL void audio_queue_player_set_volume(PhonoliteAudioPlayer *player, float volume);
PHONOLITE_QUEUE_INTERNAL void audio_queue_player_pause(PhonoliteAudioPlayer *player);
PHONOLITE_QUEUE_INTERNAL void audio_queue_player_resume(PhonoliteAudioPlayer *player);
PHONOLITE_QUEUE_INTERNAL int32_t audio_queue_player_flush(PhonoliteAudioPlayer *player);
PHONOLITE_QUEUE_INTERNAL int64_t audio_queue_player_collect_done_samples(PhonoliteAudioPlayer *player);
PHONOLITE_QUEUE_INTERNAL int32_t audio_queue_player_is_idle(PhonoliteAudioPlayer *player);

#undef PHONOLITE_QUEUE_INTERNAL

#endif
