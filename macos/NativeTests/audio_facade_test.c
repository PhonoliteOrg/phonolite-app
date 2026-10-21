#include "audio_output_devices.h"
#include "audio_queue_player.h"
#include "phonolite_audio.h"

#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

// These are doubles of the internal contracts, not substitutes for Apple APIs.
// Link the real facade against them to check opaque handles, units and return widths.
struct PhonoliteAudioPlayer {
  int marker;
};

enum AudioOperation {
  OPEN,
  CLOSE,
  WRITE,
  SET_VOLUME,
  PAUSE,
  RESUME,
  FLUSH,
  COLLECT_DONE,
  IS_IDLE,
  DEVICE_COUNT,
  DEVICE_ID,
  DEVICE_NAME,
};

static PhonoliteAudioPlayer resource = {1};
static enum AudioOperation last_operation;
static int call_count;
static PhonoliteAudioPlayer *last_player;
static const int16_t *last_samples;
static int32_t last_sample_count;
static int32_t last_sample_rate;
static int32_t last_channels;
static int32_t last_device_id;
static float last_volume;
static int32_t last_index;
static uint32_t last_name_device_id;
static char *last_name_buffer;
static int32_t last_name_length;

PhonoliteAudioPlayer *audio_queue_player_open(int32_t sample_rate, int32_t channels, int32_t device_id) {
  ++call_count;
  last_operation = OPEN;
  last_sample_rate = sample_rate;
  last_channels = channels;
  last_device_id = device_id;

  return &resource;
}

void audio_queue_player_close(PhonoliteAudioPlayer *player) {
  ++call_count;
  last_operation = CLOSE;
  last_player = player;
}

int32_t audio_queue_player_write(PhonoliteAudioPlayer *player, const int16_t *samples, int32_t sample_count) {
  ++call_count;
  last_operation = WRITE;
  last_player = player;
  last_samples = samples;
  last_sample_count = sample_count;

  return -3;
}

void audio_queue_player_set_volume(PhonoliteAudioPlayer *player, float volume) {
  ++call_count;
  last_operation = SET_VOLUME;
  last_player = player;
  last_volume = volume;
}

void audio_queue_player_pause(PhonoliteAudioPlayer *player) {
  ++call_count;
  last_operation = PAUSE;
  last_player = player;
}

void audio_queue_player_resume(PhonoliteAudioPlayer *player) {
  ++call_count;
  last_operation = RESUME;
  last_player = player;
}

int32_t audio_queue_player_flush(PhonoliteAudioPlayer *player) {
  ++call_count;
  last_operation = FLUSH;
  last_player = player;

  return -50;
}

int64_t audio_queue_player_collect_done_samples(PhonoliteAudioPlayer *player) {
  ++call_count;
  last_operation = COLLECT_DONE;
  last_player = player;

  return INT64_C(4294967297);
}

int32_t audio_queue_player_is_idle(PhonoliteAudioPlayer *player) {
  ++call_count;
  last_operation = IS_IDLE;
  last_player = player;

  return 1;
}

int32_t audio_output_devices_count(void) {
  ++call_count;
  last_operation = DEVICE_COUNT;

  return 7;
}

uint32_t audio_output_devices_id(int32_t index) {
  ++call_count;
  last_operation = DEVICE_ID;
  last_index = index;

  return UINT32_C(4294967294);
}

int32_t audio_output_devices_name(uint32_t device_id, char *buffer, int32_t buffer_length) {
  ++call_count;
  last_operation = DEVICE_NAME;
  last_name_device_id = device_id;
  last_name_buffer = buffer;
  last_name_length = buffer_length;
  memcpy(buffer, "DAC", 4);

  return -1;
}

int main(void) {
  assert(phonolite_audio_open(48000, 2, -1) == &resource);
  assert(last_operation == OPEN && call_count == 1 && last_sample_rate == 48000 && last_channels == 2 &&
         last_device_id == -1);

  phonolite_audio_close(NULL);
  assert(last_operation == CLOSE && call_count == 2 && last_player == NULL);

  const int16_t samples[] = {1, -2, 3, -4};
  assert(phonolite_audio_write(&resource, samples, 4) == -3);
  assert(last_operation == WRITE && call_count == 3 && last_player == &resource && last_samples == samples &&
         last_sample_count == 4);

  phonolite_audio_set_volume(&resource, 1.25f);
  assert(last_operation == SET_VOLUME && call_count == 4 && last_player == &resource && last_volume == 1.25f);

  phonolite_audio_pause(&resource);
  assert(last_operation == PAUSE && call_count == 5 && last_player == &resource);

  phonolite_audio_resume(NULL);
  assert(last_operation == RESUME && call_count == 6 && last_player == NULL);

  assert(phonolite_audio_flush(&resource) == -50);
  assert(last_operation == FLUSH && call_count == 7 && last_player == &resource);

  assert(phonolite_audio_collect_done_samples(&resource) == INT64_C(4294967297));
  assert(last_operation == COLLECT_DONE && call_count == 8 && last_player == &resource);

  assert(phonolite_audio_is_idle(NULL) == 1);
  assert(last_operation == IS_IDLE && call_count == 9 && last_player == NULL);

  assert(phonolite_audio_get_output_device_count() == 7);
  assert(last_operation == DEVICE_COUNT && call_count == 10);

  assert(phonolite_audio_get_output_device_id(-1) == UINT32_C(4294967294));
  assert(last_operation == DEVICE_ID && call_count == 11 && last_index == -1);

  char name[16] = {0};
  assert(phonolite_audio_get_output_device_name(UINT32_C(4294967294), name, 16) == -1);
  assert(last_operation == DEVICE_NAME && call_count == 12 && last_name_device_id == UINT32_C(4294967294));
  assert(last_name_buffer == name && last_name_length == 16 && strcmp(name, "DAC") == 0);

  puts("12 native audio facade contracts passed.");

  return 0;
}
