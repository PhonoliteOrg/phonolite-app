#ifndef PHONOLITE_AUDIO_QUEUE_BUFFER_H
#define PHONOLITE_AUDIO_QUEUE_BUFFER_H

#include "audio_queue_progress.h"
#include <AudioToolbox/AudioToolbox.h>
#include <stddef.h>

struct PhonoliteAudioBuffer {
  AudioQueueBufferRef buffer;
  int32_t sample_count;
  uint64_t generation;
  PhonoliteAudioProgressSpan progress;
  struct PhonoliteAudioBuffer *next;
};

/* Called under the queue's buffer lock after polling the playback clock. */
static inline bool phonolite_audio_queue_has_room(const struct PhonoliteAudioBuffer *entry, uint64_t generation,
                                                  int32_t sample_rate, int32_t channels, int32_t incoming_samples) {
  const int64_t capacity_samples = (int64_t)sample_rate * channels / 2; /* 500 ms */
  int64_t used_samples = 0;
  int entries = 0;
  for (; entry != NULL; entry = entry->next) {
    if (entry->generation != generation)
      continue;
    /* Bound bookkeeping even when a decoder supplies single-frame fragments. */
    if (++entries >= 256)
      return false;
    /* AudioQueue may return storage before rendering, or retain a buffer until
       after its samples have played. Charge each entry until both have drained. */
    used_samples +=
        entry->buffer != NULL ? entry->sample_count : entry->sample_count - entry->progress.rendered_samples;
  }
  /* A whole write larger than the window must still be able to make progress. */
  return used_samples == 0 || used_samples + incoming_samples <= capacity_samples;
}

#endif
