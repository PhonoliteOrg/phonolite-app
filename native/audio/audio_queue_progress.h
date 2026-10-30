#ifndef PHONOLITE_AUDIO_QUEUE_PROGRESS_H
#define PHONOLITE_AUDIO_QUEUE_PROGRESS_H

#include <math.h>
#include <stdbool.h>
#include <stdint.h>

/* A buffer-return callback releases storage; only the queue clock consumes PCM. */
typedef struct PhonoliteAudioProgressSpan {
  uint64_t generation;
  int32_t sample_count;
  int32_t channels;
  int32_t rendered_samples;
  double start_frame;
  bool scheduled;
} PhonoliteAudioProgressSpan;

static inline int64_t phonolite_progress_collect(PhonoliteAudioProgressSpan *span,
                                                 uint64_t generation, bool clock_valid,
                                                 double current_frame) {
  if (!span->scheduled || span->generation != generation || !clock_valid ||
      !isfinite(current_frame) || current_frame <= span->start_frame) {
    return 0;
  }
  const double frames = floor(current_frame - span->start_frame);
  const double maximum_frames = (double)(span->sample_count / span->channels);
  const int32_t rendered = frames >= maximum_frames ? span->sample_count
                                                   : (int32_t)frames * span->channels;
  if (rendered <= span->rendered_samples) {
    return 0;
  }
  const int64_t delta = rendered - span->rendered_samples;
  span->rendered_samples = rendered;
  return delta;
}

static inline bool phonolite_progress_pending(const PhonoliteAudioProgressSpan *span,
                                               uint64_t generation) {
  return span->generation == generation &&
         (!span->scheduled || span->rendered_samples < span->sample_count);
}

#endif
