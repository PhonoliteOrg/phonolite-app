#import "phonolite_audio.h"

#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#include <stdatomic.h>
#include <string.h>
#include <stdlib.h>

#define PHONOLITE_EXPORT __attribute__((visibility("default"))) __attribute__((used))

struct PhonoliteAudioPlayer {
  AudioQueueRef queue;
  atomic_int in_flight;
  atomic_llong completed_samples;
  int32_t sample_rate;
  int32_t channels;
};

static void phonolite_audio_output_callback(void *inUserData,
                                            AudioQueueRef inAQ,
                                            AudioQueueBufferRef inBuffer) {
  struct PhonoliteAudioPlayer *player = (struct PhonoliteAudioPlayer *)inUserData;
  if (player == NULL) {
    AudioQueueFreeBuffer(inAQ, inBuffer);
    return;
  }
  int32_t sampleCount = (int32_t)(intptr_t)inBuffer->mUserData;
  if (sampleCount > 0) {
    atomic_fetch_add(&player->completed_samples, sampleCount);
  }
  atomic_fetch_sub(&player->in_flight, 1);
  AudioQueueFreeBuffer(inAQ, inBuffer);
}

static void phonolite_audio_prepare_session(double sampleRate) {
  AVAudioSession *session = [AVAudioSession sharedInstance];
  NSError *error = nil;
  [session setCategory:AVAudioSessionCategoryPlayback error:&error];
  if (error != nil) {
    return;
  }
  if (sampleRate > 0) {
    [session setPreferredSampleRate:sampleRate error:&error];
  }
  [session setActive:YES error:&error];
}

PHONOLITE_EXPORT PhonoliteAudioPlayer *phonolite_audio_open(int32_t sampleRate,
                                                            int32_t channels,
                                                            int32_t deviceId) {
  if (sampleRate <= 0 || channels <= 0) {
    return NULL;
  }
  (void)deviceId;

  phonolite_audio_prepare_session((double)sampleRate);

  struct PhonoliteAudioPlayer *player =
      (struct PhonoliteAudioPlayer *)calloc(1, sizeof(struct PhonoliteAudioPlayer));
  if (player == NULL) {
    return NULL;
  }
  atomic_init(&player->in_flight, 0);
  atomic_init(&player->completed_samples, 0);
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
    free(player);
    return NULL;
  }

  status = AudioQueueStart(player->queue, NULL);
  if (status != noErr) {
    AudioQueueDispose(player->queue, true);
    free(player);
    return NULL;
  }

  return player;
}

PHONOLITE_EXPORT void phonolite_audio_close(PhonoliteAudioPlayer *player) {
  if (player == NULL) {
    return;
  }
  if (player->queue != NULL) {
    AudioQueueStop(player->queue, true);
    AudioQueueDispose(player->queue, true);
  }
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
  UInt32 byteSize = (UInt32)(sampleCount * (int32_t)sizeof(int16_t));
  AudioQueueBufferRef buffer = NULL;
  OSStatus status = AudioQueueAllocateBuffer(player->queue, byteSize, &buffer);
  if (status != noErr || buffer == NULL) {
    return (int32_t)status;
  }
  memcpy(buffer->mAudioData, samples, byteSize);
  buffer->mAudioDataByteSize = byteSize;
  buffer->mUserData = (void *)(intptr_t)sampleCount;

  atomic_fetch_add(&player->in_flight, 1);
  status = AudioQueueEnqueueBuffer(player->queue, buffer, 0, NULL);
  if (status != noErr) {
    atomic_fetch_sub(&player->in_flight, 1);
    AudioQueueFreeBuffer(player->queue, buffer);
    return (int32_t)status;
  }
  return 0;
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
  AudioQueuePause(player->queue);
}

PHONOLITE_EXPORT void phonolite_audio_resume(PhonoliteAudioPlayer *player) {
  if (player == NULL || player->queue == NULL) {
    return;
  }
  AudioQueueStart(player->queue, NULL);
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
