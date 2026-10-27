#include "audio_queue_player.h"

#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>

#include <pthread.h>
#include <limits.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

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
  int32_t bits_per_sample;
  bool paused;
  bool started;
  OSStatus output_error;
  pthread_mutex_t buffer_lock;
  uint64_t generation;
  struct PhonoliteAudioBuffer *buffers;
};

static const int max_in_flight = 5;
static const int queue_full = -3;

static void audio_queue_player_release_buffer(PhonoliteAudioPlayer *player, AudioQueueRef queue,
                                              AudioQueueBufferRef buffer, bool completed) {
  pthread_mutex_lock(&player->buffer_lock);

  struct PhonoliteAudioBuffer **link = &player->buffers;
  while (*link != NULL && (*link)->buffer != buffer) {
    link = &(*link)->next;
  }

  struct PhonoliteAudioBuffer *entry = *link;
  if (entry != NULL) {
    *link = entry->next;

    // A completion from a reset must not change the next generation's counters.
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

static void audio_queue_player_output_callback(void *user_data, AudioQueueRef queue, AudioQueueBufferRef buffer) {
  PhonoliteAudioPlayer *player = (PhonoliteAudioPlayer *)user_data;
  if (player != NULL) {
    audio_queue_player_release_buffer(player, queue, buffer, true);
  }
}

static OSStatus audio_queue_player_start_if_ready(PhonoliteAudioPlayer *player) {
  if (player->paused || player->started || atomic_load(&player->in_flight) == 0) {
    return noErr;
  }

  OSStatus status = AudioQueueStart(player->queue, NULL);
  if (status == noErr) {
    player->started = true;
  } else {
    player->output_error = status;
  }

  return status;
}

PhonoliteAudioPlayer *audio_queue_player_open(int32_t sample_rate, int32_t channels, int32_t device_id) {
  return audio_queue_player_open_format(sample_rate, channels, device_id, 16);
}

PhonoliteAudioPlayer *audio_queue_player_open_format(int32_t sample_rate, int32_t channels, int32_t device_id,
                                                    int32_t bits_per_sample) {
  if (sample_rate <= 0 || channels <= 0 || channels > 32 ||
      (bits_per_sample != 16 && bits_per_sample != 32)) {
    return NULL;
  }

  struct PhonoliteAudioPlayer *player = (struct PhonoliteAudioPlayer *)calloc(1, sizeof(struct PhonoliteAudioPlayer));
  if (player == NULL) {
    return NULL;
  }

  atomic_init(&player->in_flight, 0);
  atomic_init(&player->completed_samples, 0);
  pthread_mutex_init(&player->buffer_lock, NULL);
  player->sample_rate = sample_rate;
  player->channels = channels;
  player->bits_per_sample = bits_per_sample;

  AudioStreamBasicDescription asbd;
  memset(&asbd, 0, sizeof(asbd));
  asbd.mSampleRate = sample_rate;
  asbd.mFormatID = kAudioFormatLinearPCM;
  asbd.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
  asbd.mBytesPerPacket = (UInt32)(channels * bits_per_sample / 8);
  asbd.mFramesPerPacket = 1;
  asbd.mBytesPerFrame = (UInt32)(channels * bits_per_sample / 8);
  asbd.mChannelsPerFrame = (UInt32)channels;
  asbd.mBitsPerChannel = (UInt32)bits_per_sample;

  OSStatus status =
      AudioQueueNewOutput(&asbd, audio_queue_player_output_callback, player, NULL, NULL, 0, &player->queue);
  if (status != noErr || player->queue == NULL) {
    pthread_mutex_destroy(&player->buffer_lock);
    free(player);
    return NULL;
  }

  // Preserve the existing best-effort numeric device property attempt.
  if (device_id >= 0) {
    AudioDeviceID device = (AudioDeviceID)device_id;
    status = AudioQueueSetProperty(player->queue, kAudioQueueProperty_CurrentDevice, &device, sizeof(device));
    (void)status;
  }

  // Start only when the first PCM buffer is ready.
  return player;
}

void audio_queue_player_close(PhonoliteAudioPlayer *player) {
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

  // Synchronous disposal releases the AudioQueue buffers; only bookkeeping remains.
  while (player->buffers != NULL) {
    struct PhonoliteAudioBuffer *entry = player->buffers;
    player->buffers = entry->next;
    free(entry);
  }

  pthread_mutex_destroy(&player->buffer_lock);
  free(player);
}

static int32_t audio_queue_player_write_pcm(PhonoliteAudioPlayer *player, const void *samples, int32_t sample_count,
                                            int32_t bits_per_sample) {
  if (player == NULL || samples == NULL || sample_count <= 0 || player->bits_per_sample != bits_per_sample ||
      sample_count % player->channels != 0 || sample_count > INT32_MAX / (bits_per_sample / 8)) {
    return -1;
  }

  if (player->queue == NULL) {
    return -2;
  }

  if (player->output_error != noErr) {
    return (int32_t)player->output_error;
  }

  if (atomic_load(&player->in_flight) >= max_in_flight) {
    return queue_full;
  }

  struct PhonoliteAudioBuffer *entry = calloc(1, sizeof(*entry));
  if (entry == NULL) {
    return -4;
  }

  UInt32 byte_size = (UInt32)(sample_count * (bits_per_sample / 8));
  AudioQueueBufferRef buffer = NULL;
  OSStatus status = AudioQueueAllocateBuffer(player->queue, byte_size, &buffer);
  if (status != noErr || buffer == NULL) {
    free(entry);
    return (int32_t)status;
  }

  memcpy(buffer->mAudioData, samples, byte_size);
  buffer->mAudioDataByteSize = byte_size;
  entry->buffer = buffer;
  entry->sample_count = sample_count;

  pthread_mutex_lock(&player->buffer_lock);
  entry->generation = player->generation;
  entry->next = player->buffers;
  player->buffers = entry;
  atomic_fetch_add(&player->in_flight, 1);
  pthread_mutex_unlock(&player->buffer_lock);

  status = AudioQueueEnqueueBuffer(player->queue, buffer, 0, NULL);
  if (status != noErr) {
    audio_queue_player_release_buffer(player, player->queue, buffer, false);
    return (int32_t)status;
  }

  return (int32_t)audio_queue_player_start_if_ready(player);
}

int32_t audio_queue_player_write(PhonoliteAudioPlayer *player, const int16_t *samples, int32_t sample_count) {
  return audio_queue_player_write_pcm(player, samples, sample_count, 16);
}

int32_t audio_queue_player_write32(PhonoliteAudioPlayer *player, const int32_t *samples, int32_t sample_count) {
  return audio_queue_player_write_pcm(player, samples, sample_count, 32);
}

int32_t audio_queue_player_flush(PhonoliteAudioPlayer *player) {
  if (player == NULL || player->queue == NULL) {
    return -1;
  }

  pthread_mutex_lock(&player->buffer_lock);
  player->generation++;
  atomic_store(&player->in_flight, 0);
  atomic_store(&player->completed_samples, 0);
  pthread_mutex_unlock(&player->buffer_lock);

  // Keep the route and paused state while invalidating old buffer accounting.
  if (player->started) {
    AudioQueuePause(player->queue);
  }

  player->started = false;
  OSStatus status = AudioQueueReset(player->queue);
  player->output_error = status;

  return (int32_t)status;
}

void audio_queue_player_set_volume(PhonoliteAudioPlayer *player, float volume) {
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

void audio_queue_player_pause(PhonoliteAudioPlayer *player) {
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

void audio_queue_player_resume(PhonoliteAudioPlayer *player) {
  if (player == NULL || player->queue == NULL) {
    return;
  }

  player->paused = false;
  player->output_error = noErr;
  audio_queue_player_start_if_ready(player);
}

int64_t audio_queue_player_collect_done_samples(PhonoliteAudioPlayer *player) {
  if (player == NULL) {
    return 0;
  }

  return (int64_t)atomic_exchange(&player->completed_samples, 0);
}

int32_t audio_queue_player_is_idle(PhonoliteAudioPlayer *player) {
  if (player == NULL) {
    return 1;
  }

  return atomic_load(&player->in_flight) == 0 ? 1 : 0;
}
