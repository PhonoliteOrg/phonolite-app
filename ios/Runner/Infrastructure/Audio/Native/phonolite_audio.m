#import "phonolite_audio.h"

#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#include <stdatomic.h>
#include <limits.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>
#include <pthread.h>
#include "../../../../../native/audio/audio_queue_progress.h"

#define PHONOLITE_EXPORT __attribute__((visibility("default"))) __attribute__((used))

struct PhonoliteAudioBuffer {
  AudioQueueBufferRef buffer;
  int32_t sample_count;
  uint64_t generation;
  PhonoliteAudioProgressSpan progress;
  struct PhonoliteAudioBuffer *next;
};

struct PhonoliteAudioPlayer {
  AudioQueueRef queue;
  atomic_int in_flight;
  int64_t pending_done_samples;
  AudioQueueTimelineRef timeline;
  double scheduled_end_frame;
  bool has_schedule;
  bool clock_observed;
  int32_t channels;
  int32_t bits_per_sample;
  bool paused;
  bool started;
  OSStatus output_error;
  pthread_mutex_t buffer_lock;
  uint64_t generation;
  struct PhonoliteAudioBuffer *buffers;
};

static const int kPhonoliteMaxInFlight = 5;
static const int kPhonoliteQueueFull = -3;

static bool phonolite_audio_current_frame(PhonoliteAudioPlayer *player, double *frame) {
  AudioTimeStamp time = {0};
  Boolean discontinuity = false;
  OSStatus status = AudioQueueGetCurrentTime(player->queue, player->timeline, &time, &discontinuity);
  if (status != noErr || !(time.mFlags & kAudioTimeStampSampleTimeValid) || !isfinite(time.mSampleTime)) {
    // A queue may have no hardware clock until its first start, or while paused.
    if (player->started && player->clock_observed) player->output_error = status != noErr ? status : kAudioQueueErr_InvalidRunState;
    return false;
  }
  if (discontinuity && player->clock_observed) {
    player->output_error = kAudioQueueErr_InvalidRunState;
    return false;
  }
  if (player->started) player->clock_observed = true;
  *frame = time.mSampleTime;
  return true;
}

static int32_t phonolite_audio_poll_progress(PhonoliteAudioPlayer *player) {
  if (player->output_error != noErr) return -1;
  double frame = 0;
  const bool valid = phonolite_audio_current_frame(player, &frame);
  if (player->output_error != noErr) return -1;
  pthread_mutex_lock(&player->buffer_lock);
  struct PhonoliteAudioBuffer **link = &player->buffers;
  while (*link != NULL) {
    struct PhonoliteAudioBuffer *entry = *link;
    player->pending_done_samples += phonolite_progress_collect(&entry->progress, player->generation, valid, frame);
    if (entry->buffer == NULL && !phonolite_progress_pending(&entry->progress, player->generation)) {
      *link = entry->next;
      free(entry);
    } else {
      link = &entry->next;
    }
  }
  pthread_mutex_unlock(&player->buffer_lock);
  return 0;
}

static int32_t phonolite_audio_pending_spans(PhonoliteAudioPlayer *player) {
  int32_t count = 0;
  pthread_mutex_lock(&player->buffer_lock);
  for (struct PhonoliteAudioBuffer *entry = player->buffers; entry != NULL; entry = entry->next) {
    if (phonolite_progress_pending(&entry->progress, player->generation)) count++;
  }
  pthread_mutex_unlock(&player->buffer_lock);
  return count;
}

static void phonolite_audio_release_buffer(PhonoliteAudioPlayer *player, AudioQueueRef queue,
                                  AudioQueueBufferRef buffer, bool completed) {
  pthread_mutex_lock(&player->buffer_lock);
  struct PhonoliteAudioBuffer **link = &player->buffers;
  while (*link != NULL && (*link)->buffer != buffer) link = &(*link)->next;
  struct PhonoliteAudioBuffer *entry = *link;
  bool remove = false;
  if (entry != NULL) {
    entry->buffer = NULL;
    if (entry->generation == player->generation) atomic_fetch_sub(&player->in_flight, 1);
    // A returned buffer is reusable before its audio is rendered. Retain its
    // clock span; failed enqueues and cancelled generations have no PCM to play.
    remove = !completed || entry->generation != player->generation ||
             (entry->progress.scheduled && !phonolite_progress_pending(&entry->progress, player->generation));
    if (remove) *link = entry->next;
  }
  pthread_mutex_unlock(&player->buffer_lock);
  if (entry != NULL) {
    AudioQueueFreeBuffer(queue, buffer);
    if (remove) free(entry);
  }
}

static void phonolite_audio_output_callback(void *inUserData,
                                            AudioQueueRef inAQ,
                                            AudioQueueBufferRef inBuffer) {
  PhonoliteAudioPlayer *player = (PhonoliteAudioPlayer *)inUserData;
  if (player != NULL) {
    phonolite_audio_release_buffer(player, inAQ, inBuffer, true);
  }
}

static bool phonolite_audio_prepare_session(void) {
  AVAudioSession *session = [AVAudioSession sharedInstance];
  NSError *error = nil;
  // Avoid changing hardware preferences on every track transition. AudioQueue
  // converts each track's sample rate to the current route's hardware rate.
  if (![session.category isEqualToString:AVAudioSessionCategoryPlayback] ||
      ![session.mode isEqualToString:AVAudioSessionModeDefault] || session.categoryOptions != 0) {
    if (![session setCategory:AVAudioSessionCategoryPlayback
                  mode:AVAudioSessionModeDefault
               options:0
                 error:&error]) {
      NSLog(@"Phonolite audio category failed: %@", error);
      return false;
    }
  }
  if (![session setActive:YES error:&error]) {
    NSLog(@"Phonolite audio activation failed: %@", error);
    return false;
  }
  return true;
}

static OSStatus phonolite_audio_start_if_ready(PhonoliteAudioPlayer *player) {
  if (player->paused || player->started ||
      (atomic_load(&player->in_flight) == 0 && phonolite_audio_pending_spans(player) == 0)) {
    return noErr;
  }
  OSStatus status = AudioQueueStart(player->queue, NULL);
  if (status == noErr) {
    player->started = true;
  } else {
    player->output_error = status;
    NSLog(@"Phonolite audio start failed: %d", (int)status);
  }
  return status;
}

PHONOLITE_EXPORT PhonoliteAudioPlayer *phonolite_audio_open(int32_t sampleRate,
                                                            int32_t channels,
                                                            int32_t deviceId) {
  return phonolite_audio_open_format(sampleRate, channels, deviceId, 16);
}

PHONOLITE_EXPORT PhonoliteAudioPlayer *phonolite_audio_open_format(int32_t sampleRate, int32_t channels,
                                                                   int32_t deviceId, int32_t bitsPerSample) {
  if (sampleRate <= 0 || channels <= 0 || channels > 32 || (bitsPerSample != 16 && bitsPerSample != 32)) {
    return NULL;
  }
  (void)deviceId;

  if (!phonolite_audio_prepare_session()) {
    return NULL;
  }

  struct PhonoliteAudioPlayer *player =
      (struct PhonoliteAudioPlayer *)calloc(1, sizeof(struct PhonoliteAudioPlayer));
  if (player == NULL) {
    return NULL;
  }
  atomic_init(&player->in_flight, 0);
  pthread_mutex_init(&player->buffer_lock, NULL);
  player->channels = channels;
  player->bits_per_sample = bitsPerSample;

  AudioStreamBasicDescription asbd;
  memset(&asbd, 0, sizeof(asbd));
  asbd.mSampleRate = sampleRate;
  asbd.mFormatID = kAudioFormatLinearPCM;
  asbd.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
  asbd.mBytesPerPacket = (UInt32)(channels * bitsPerSample / 8);
  asbd.mFramesPerPacket = 1;
  asbd.mBytesPerFrame = (UInt32)(channels * bitsPerSample / 8);
  asbd.mChannelsPerFrame = (UInt32)channels;
  asbd.mBitsPerChannel = (UInt32)bitsPerSample;

  OSStatus status = AudioQueueNewOutput(&asbd,
                                        phonolite_audio_output_callback,
                                        player,
                                        NULL,
                                        NULL,
                                        0,
                                        &player->queue);
  if (status != noErr || player->queue == NULL) {
    pthread_mutex_destroy(&player->buffer_lock);
    free(player);
    return NULL;
  }

  status = AudioQueueCreateTimeline(player->queue, &player->timeline);
  if (status != noErr) {
    AudioQueueDispose(player->queue, true);
    pthread_mutex_destroy(&player->buffer_lock);
    free(player);
    return NULL;
  }

  // Start only after the first buffer is enqueued, including after Next/seek.
  return player;
}

PHONOLITE_EXPORT void phonolite_audio_close(PhonoliteAudioPlayer *player) {
  if (player == NULL) {
    return;
  }
  if (player->queue != NULL) {
    pthread_mutex_lock(&player->buffer_lock);
    player->generation++;
    pthread_mutex_unlock(&player->buffer_lock);
    AudioQueueStop(player->queue, true);
    if (player->timeline != NULL) AudioQueueDisposeTimeline(player->queue, player->timeline);
    AudioQueueDispose(player->queue, true);
  }
  // Synchronous disposal frees any buffers not returned by a callback.
  while (player->buffers != NULL) {
    struct PhonoliteAudioBuffer *entry = player->buffers;
    player->buffers = entry->next;
    free(entry);
  }
  pthread_mutex_destroy(&player->buffer_lock);
  free(player);
}

static int32_t phonolite_audio_write_pcm(PhonoliteAudioPlayer *player, const void *samples, int32_t sampleCount,
                                         int32_t bitsPerSample) {
  if (player == NULL || samples == NULL || sampleCount <= 0 || player->bits_per_sample != bitsPerSample ||
      sampleCount % player->channels != 0 || sampleCount > INT32_MAX / (bitsPerSample / 8)) {
    return -1;
  }
  if (player->queue == NULL) {
    return -2;
  }
  if (player->output_error != noErr) {
    return (int32_t)player->output_error;
  }
  if (phonolite_audio_poll_progress(player) != 0) return -2;
  if (atomic_load(&player->in_flight) >= kPhonoliteMaxInFlight || phonolite_audio_pending_spans(player) >= kPhonoliteMaxInFlight) {
    return kPhonoliteQueueFull;
  }
  struct PhonoliteAudioBuffer *entry = calloc(1, sizeof(*entry));
  if (entry == NULL) {
    return -4;
  }
  UInt32 byteSize = (UInt32)(sampleCount * (bitsPerSample / 8));
  AudioQueueBufferRef buffer = NULL;
  OSStatus status = AudioQueueAllocateBuffer(player->queue, byteSize, &buffer);
  if (status != noErr || buffer == NULL) {
    free(entry);
    return (int32_t)status;
  }
  memcpy(buffer->mAudioData, samples, byteSize);
  buffer->mAudioDataByteSize = byteSize;
  entry->buffer = buffer;
  entry->sample_count = sampleCount;
  pthread_mutex_lock(&player->buffer_lock);
  entry->generation = player->generation;
  entry->progress.generation = player->generation;
  entry->next = player->buffers;
  player->buffers = entry;
  atomic_fetch_add(&player->in_flight, 1);
  pthread_mutex_unlock(&player->buffer_lock);
  double start_frame = player->has_schedule ? player->scheduled_end_frame : 0;
  double now = 0;
  if (phonolite_audio_current_frame(player, &now) && now > start_frame) start_frame = now;
  AudioTimeStamp actual_start = {0};
  status = AudioQueueEnqueueBufferWithParameters(player->queue, buffer, 0, NULL, 0, 0, 0, NULL,
                                                NULL, &actual_start);
  if (status != noErr) {
    phonolite_audio_release_buffer(player, player->queue, buffer, false);
    return (int32_t)status;
  }
  if ((actual_start.mFlags & kAudioTimeStampSampleTimeValid) && isfinite(actual_start.mSampleTime)) {
    start_frame = actual_start.mSampleTime;
  }
  pthread_mutex_lock(&player->buffer_lock);
  entry->progress = (PhonoliteAudioProgressSpan){player->generation, sampleCount, player->channels, 0, start_frame, true};
  player->scheduled_end_frame = start_frame + (double)(sampleCount / player->channels);
  player->has_schedule = true;
  pthread_mutex_unlock(&player->buffer_lock);
  return (int32_t)phonolite_audio_start_if_ready(player);
}

PHONOLITE_EXPORT int32_t phonolite_audio_write(PhonoliteAudioPlayer *player, const int16_t *samples,
                                               int32_t sampleCount) {
  return phonolite_audio_write_pcm(player, samples, sampleCount, 16);
}

PHONOLITE_EXPORT int32_t phonolite_audio_write32(PhonoliteAudioPlayer *player, const int32_t *samples,
                                                 int32_t sampleCount) {
  return phonolite_audio_write_pcm(player, samples, sampleCount, 32);
}

PHONOLITE_EXPORT int32_t phonolite_audio_flush(PhonoliteAudioPlayer *player) {
  if (player == NULL || player->queue == NULL) {
    return -1;
  }
  pthread_mutex_lock(&player->buffer_lock);
  player->generation++;
  atomic_store(&player->in_flight, 0);
  player->pending_done_samples = 0;
  player->has_schedule = false;
  player->clock_observed = false;
  pthread_mutex_unlock(&player->buffer_lock);
  // Retain the queue, route and user's paused state. Reset returns old buffers
  // through the callback, which frees them without counting cancelled audio.
  if (player->started) {
    AudioQueuePause(player->queue);
  }
  player->started = false;
  OSStatus status = AudioQueueReset(player->queue);
  if (status == noErr) {
    if (player->timeline != NULL) AudioQueueDisposeTimeline(player->queue, player->timeline);
    player->timeline = NULL;
    status = AudioQueueCreateTimeline(player->queue, &player->timeline);
  }
  player->output_error = status;
  return (int32_t)status;
}

PHONOLITE_EXPORT void phonolite_audio_set_volume(PhonoliteAudioPlayer *player, float volume) {
  if (player == NULL || player->queue == NULL) {
    return;
  }
  if (volume < 0.0f) {
    volume = 0.0f;
  } else if (volume > 1.0f) {
    volume = 1.0f;
  }
  AudioQueueSetParameter(player->queue, kAudioQueueParam_Volume, volume);
}

PHONOLITE_EXPORT void phonolite_audio_pause(PhonoliteAudioPlayer *player) {
  if (player == NULL || player->queue == NULL) {
    return;
  }
  player->paused = true;
  if (player->started) {
    OSStatus status = AudioQueuePause(player->queue);
    if (status != noErr) {
      player->output_error = status;
    }
    player->started = false;
  }
}

PHONOLITE_EXPORT void phonolite_audio_resume(PhonoliteAudioPlayer *player) {
  if (player == NULL || player->queue == NULL) {
    return;
  }
  player->paused = false;
  if (!phonolite_audio_prepare_session()) {
    player->output_error = kAudioQueueErr_InvalidRunState;
    return;
  }
  player->output_error = noErr;
  phonolite_audio_start_if_ready(player);
}

PHONOLITE_EXPORT int64_t phonolite_audio_collect_done_samples(PhonoliteAudioPlayer *player) {
  if (player == NULL) {
    return 0;
  }
  if (phonolite_audio_poll_progress(player) != 0) return -1;
  const int64_t done = player->pending_done_samples;
  player->pending_done_samples = 0;
  return done;
}

PHONOLITE_EXPORT int32_t phonolite_audio_is_idle(PhonoliteAudioPlayer *player) {
  if (player == NULL) {
    return 1;
  }
  if (phonolite_audio_poll_progress(player) != 0) return -1;
  return phonolite_audio_pending_spans(player) == 0 ? 1 : 0;
}

PHONOLITE_EXPORT int32_t phonolite_audio_get_output_device_count(void) {
  return 0;
}

PHONOLITE_EXPORT uint32_t phonolite_audio_get_output_device_id(int32_t index) {
  (void)index;
  return 0;
}

PHONOLITE_EXPORT int32_t phonolite_audio_get_output_device_name(uint32_t deviceId,
                                                               char *buffer,
                                                               int32_t bufferLen) {
  (void)deviceId;
  if (buffer == NULL || bufferLen <= 0) {
    return -1;
  }
  buffer[0] = '\0';
  return -1;
}
