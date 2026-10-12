#import "phonolite_audio.h"

#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>
#include <pthread.h>

#define PHONOLITE_EXPORT __attribute__((visibility("default"))) __attribute__((used))

struct PhonoliteAudioBuffer {
  AudioQueueBufferRef buffer;
  int32_t sample_count;
  uint64_t generation;
  struct PhonoliteAudioBuffer *next;
};

struct PhonoliteAudioPlayer {
  AudioQueueRef queue;
  atomic_int in_flight;
  atomic_llong completed_samples;
  int32_t sample_rate;
  int32_t channels;
  bool paused;
  bool started;
  OSStatus output_error;
  pthread_mutex_t buffer_lock;
  uint64_t generation;
  struct PhonoliteAudioBuffer *buffers;
};

static const int kPhonoliteMaxInFlight = 5;
static const int kPhonoliteQueueFull = -3;

static void phonolite_audio_release_buffer(PhonoliteAudioPlayer *player,
                                           AudioQueueRef queue,
                                           AudioQueueBufferRef buffer,
                                           bool completed) {
  pthread_mutex_lock(&player->buffer_lock);
  struct PhonoliteAudioBuffer **link = &player->buffers;
  while (*link != NULL && (*link)->buffer != buffer) {
    link = &(*link)->next;
  }
  struct PhonoliteAudioBuffer *entry = *link;
  if (entry != NULL) {
    *link = entry->next;
    // A callback from a reset must not change the next generation's counters.
    if (entry->generation == player->generation) {
      if (completed) {
        atomic_fetch_add(&player->completed_samples, entry->sample_count);
      }
      atomic_fetch_sub(&player->in_flight, 1);
    }
  }
  pthread_mutex_unlock(&player->buffer_lock);
  if (entry != NULL) {
    free(entry);
    AudioQueueFreeBuffer(queue, buffer);
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
  if (player->paused || player->started || atomic_load(&player->in_flight) == 0) {
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
  if (sampleRate <= 0 || channels <= 0) {
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
  atomic_init(&player->completed_samples, 0);
  pthread_mutex_init(&player->buffer_lock, NULL);
  player->sample_rate = sampleRate;
  player->channels = channels;

  AudioStreamBasicDescription asbd;
  memset(&asbd, 0, sizeof(asbd));
  asbd.mSampleRate = sampleRate;
  asbd.mFormatID = kAudioFormatLinearPCM;
  asbd.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
  asbd.mBytesPerPacket = (UInt32)(channels * 2);
  asbd.mFramesPerPacket = 1;
  asbd.mBytesPerFrame = (UInt32)(channels * 2);
  asbd.mChannelsPerFrame = (UInt32)channels;
  asbd.mBitsPerChannel = 16;

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

PHONOLITE_EXPORT int32_t phonolite_audio_write(PhonoliteAudioPlayer *player,
                                               const int16_t *samples,
                                               int32_t sampleCount) {
  if (player == NULL || samples == NULL || sampleCount <= 0) {
    return -1;
  }
  if (player->queue == NULL) {
    return -2;
  }
  if (player->output_error != noErr) {
    return (int32_t)player->output_error;
  }
  if (atomic_load(&player->in_flight) >= kPhonoliteMaxInFlight) {
    return kPhonoliteQueueFull;
  }
  struct PhonoliteAudioBuffer *entry = calloc(1, sizeof(*entry));
  if (entry == NULL) {
    return -4;
  }
  UInt32 byteSize = (UInt32)(sampleCount * (int32_t)sizeof(int16_t));
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
  entry->next = player->buffers;
  player->buffers = entry;
  atomic_fetch_add(&player->in_flight, 1);
  pthread_mutex_unlock(&player->buffer_lock);
  status = AudioQueueEnqueueBuffer(player->queue, buffer, 0, NULL);
  if (status != noErr) {
    phonolite_audio_release_buffer(player, player->queue, buffer, false);
    return (int32_t)status;
  }
  return (int32_t)phonolite_audio_start_if_ready(player);
}

PHONOLITE_EXPORT int32_t phonolite_audio_flush(PhonoliteAudioPlayer *player) {
  if (player == NULL || player->queue == NULL) {
    return -1;
  }
  pthread_mutex_lock(&player->buffer_lock);
  player->generation++;
  atomic_store(&player->in_flight, 0);
  atomic_store(&player->completed_samples, 0);
  pthread_mutex_unlock(&player->buffer_lock);
  // Retain the queue, route and user's paused state. Reset returns old buffers
  // through the callback, which frees them without counting cancelled audio.
  if (player->started) {
    AudioQueuePause(player->queue);
  }
  player->started = false;
  OSStatus status = AudioQueueReset(player->queue);
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
  return (int64_t)atomic_exchange(&player->completed_samples, 0);
}

PHONOLITE_EXPORT int32_t phonolite_audio_is_idle(PhonoliteAudioPlayer *player) {
  if (player == NULL) {
    return 1;
  }
  return atomic_load(&player->in_flight) == 0 ? 1 : 0;
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
