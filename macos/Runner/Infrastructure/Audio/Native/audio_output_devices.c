#include "audio_output_devices.h"

#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>

#include <stdlib.h>

static int device_is_alive(AudioDeviceID device) {
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

static int device_has_output(AudioDeviceID device) {
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

  AudioBufferList *buffer_list = (AudioBufferList *)malloc(size);
  if (buffer_list == NULL) {
    return 0;
  }

  status = AudioObjectGetPropertyData(device, &address, 0, NULL, &size, buffer_list);
  if (status != noErr) {
    free(buffer_list);
    return 0;
  }

  int channels = 0;
  for (UInt32 i = 0; i < buffer_list->mNumberBuffers; i++) {
    channels += (int)buffer_list->mBuffers[i].mNumberChannels;
  }

  free(buffer_list);

  return channels > 0;
}

static int get_all_devices(AudioDeviceID **out_devices, UInt32 *out_count) {
  if (out_devices == NULL || out_count == NULL) {
    return 0;
  }

  AudioObjectPropertyAddress address = {
      kAudioHardwarePropertyDevices,
      kAudioObjectPropertyScopeGlobal,
      kAudioObjectPropertyElementMain,
  };
  UInt32 size = 0;
  OSStatus status = AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address, 0, NULL, &size);
  if (status != noErr || size == 0) {
    return 0;
  }

  UInt32 count = size / sizeof(AudioDeviceID);
  AudioDeviceID *devices = (AudioDeviceID *)malloc(size);
  if (devices == NULL) {
    return 0;
  }

  status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, devices);
  if (status != noErr) {
    free(devices);
    return 0;
  }

  *out_devices = devices;
  *out_count = count;

  return 1;
}

int32_t audio_output_devices_count(void) {
  AudioDeviceID *devices = NULL;
  UInt32 count = 0;
  if (!get_all_devices(&devices, &count)) {
    return 0;
  }

  int32_t output_count = 0;
  for (UInt32 i = 0; i < count; i++) {
    AudioDeviceID device = devices[i];
    if (!device_is_alive(device)) {
      continue;
    }

    if (device_has_output(device)) {
      output_count++;
    }
  }

  free(devices);

  return output_count;
}

uint32_t audio_output_devices_id(int32_t index) {
  if (index < 0) {
    return 0;
  }

  AudioDeviceID *devices = NULL;
  UInt32 count = 0;
  if (!get_all_devices(&devices, &count)) {
    return 0;
  }

  int32_t current = 0;
  uint32_t result = 0;
  for (UInt32 i = 0; i < count; i++) {
    AudioDeviceID device = devices[i];
    if (!device_is_alive(device)) {
      continue;
    }

    if (!device_has_output(device)) {
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

int32_t audio_output_devices_name(uint32_t device_id, char *buffer, int32_t buffer_length) {
  if (buffer == NULL || buffer_length <= 0) {
    return -1;
  }

  buffer[0] = '\0';
  AudioDeviceID device = (AudioDeviceID)device_id;
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

  Boolean ok = CFStringGetCString(name, buffer, buffer_length, kCFStringEncodingUTF8);
  CFRelease(name);
  if (!ok) {
    buffer[0] = '\0';
    return -1;
  }

  return 0;
}
