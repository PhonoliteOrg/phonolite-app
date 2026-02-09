#include "phonolite_audio.h"

#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

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

PHONOLITE_EXPORT PhonoliteAudioPlayer *phonolite_audio_open(int32_t sampleRate,
                                                            int32_t channels,
                                                            int32_t deviceId) {
  if (sampleRate <= 0 || channels <= 0) {
    return NULL;
  }
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

  if (deviceId >= 0) {
    AudioDeviceID device = (AudioDeviceID)deviceId;
    status = AudioQueueSetProperty(player->queue,
                                   kAudioQueueProperty_CurrentDevice,
                                   &device,
                                   sizeof(device));
    (void)status;
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

static int phonolite_device_is_alive(AudioDeviceID device) {
  UInt32 alive = 0;
  UInt32 size = sizeof(alive);
  AudioObjectPropertyAddress address = {
      kAudioDevicePropertyDeviceIsAlive,
      kAudioObjectPropertyScopeGlobal,
      kAudioObjectPropertyElementMain,
  };
  OSStatus status = AudioObjectGetPropertyData(device, &address, 0, NULL, &size, &alive);
  if (status != noErr) {
    return 0;
  }
  return alive != 0;
}

static int phonolite_device_has_output(AudioDeviceID device) {
  AudioObjectPropertyAddress address = {
      kAudioDevicePropertyStreamConfiguration,
      kAudioDevicePropertyScopeOutput,
      kAudioObjectPropertyElementMain,
  };
  UInt32 size = 0;
  OSStatus status = AudioObjectGetPropertyDataSize(device, &address, 0, NULL, &size);
  if (status != noErr || size == 0) {
    return 0;
  }
  AudioBufferList *bufferList = (AudioBufferList *)malloc(size);
  if (bufferList == NULL) {
    return 0;
  }
  status = AudioObjectGetPropertyData(device, &address, 0, NULL, &size, bufferList);
  if (status != noErr) {
    free(bufferList);
    return 0;
  }
  int channels = 0;
  for (UInt32 i = 0; i < bufferList->mNumberBuffers; i++) {
    channels += (int)bufferList->mBuffers[i].mNumberChannels;
  }
  free(bufferList);
  return channels > 0;
}

static int phonolite_get_all_devices(AudioDeviceID **outDevices, UInt32 *outCount) {
  if (outDevices == NULL || outCount == NULL) {
    return 0;
  }
  AudioObjectPropertyAddress address = {
      kAudioHardwarePropertyDevices,
      kAudioObjectPropertyScopeGlobal,
      kAudioObjectPropertyElementMain,
  };
  UInt32 size = 0;
  OSStatus status = AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,
                                                   &address,
                                                   0,
                                                   NULL,
                                                   &size);
  if (status != noErr || size == 0) {
    return 0;
  }
  UInt32 count = size / sizeof(AudioDeviceID);
  AudioDeviceID *devices = (AudioDeviceID *)malloc(size);
  if (devices == NULL) {
    return 0;
  }
  status = AudioObjectGetPropertyData(kAudioObjectSystemObject,
                                      &address,
                                      0,
                                      NULL,
                                      &size,
                                      devices);
  if (status != noErr) {
    free(devices);
    return 0;
  }
  *outDevices = devices;
  *outCount = count;
  return 1;
}

PHONOLITE_EXPORT int32_t phonolite_audio_get_output_device_count(void) {
  AudioDeviceID *devices = NULL;
  UInt32 count = 0;
  if (!phonolite_get_all_devices(&devices, &count)) {
    return 0;
  }
  int32_t outputCount = 0;
  for (UInt32 i = 0; i < count; i++) {
    AudioDeviceID device = devices[i];
    if (!phonolite_device_is_alive(device)) {
      continue;
    }
    if (phonolite_device_has_output(device)) {
      outputCount++;
    }
  }
  free(devices);
  return outputCount;
}

PHONOLITE_EXPORT uint32_t phonolite_audio_get_output_device_id(int32_t index) {
  if (index < 0) {
    return 0;
  }
  AudioDeviceID *devices = NULL;
  UInt32 count = 0;
  if (!phonolite_get_all_devices(&devices, &count)) {
    return 0;
  }
  int32_t current = 0;
  uint32_t result = 0;
  for (UInt32 i = 0; i < count; i++) {
    AudioDeviceID device = devices[i];
    if (!phonolite_device_is_alive(device)) {
      continue;
    }
    if (!phonolite_device_has_output(device)) {
      continue;
    }
    if (current == index) {
      result = (uint32_t)device;
      break;
    }
    current++;
  }
  free(devices);
  return result;
}

PHONOLITE_EXPORT int32_t phonolite_audio_get_output_device_name(uint32_t deviceId,
                                                               char *buffer,
                                                               int32_t bufferLen) {
  if (buffer == NULL || bufferLen <= 0) {
    return -1;
  }
  buffer[0] = '\0';
  AudioDeviceID device = (AudioDeviceID)deviceId;
  CFStringRef name = NULL;
  UInt32 size = sizeof(name);
  AudioObjectPropertyAddress address = {
      kAudioObjectPropertyName,
      kAudioObjectPropertyScopeGlobal,
      kAudioObjectPropertyElementMain,
  };
  OSStatus status = AudioObjectGetPropertyData(device, &address, 0, NULL, &size, &name);
  if (status != noErr || name == NULL) {
    return -1;
  }
  Boolean ok = CFStringGetCString(name, buffer, bufferLen, kCFStringEncodingUTF8);
  CFRelease(name);
  if (!ok) {
    buffer[0] = '\0';
    return -1;
  }
  return 0;
}
