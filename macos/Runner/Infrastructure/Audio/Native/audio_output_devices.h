#ifndef AUDIO_OUTPUT_DEVICES_H
#define AUDIO_OUTPUT_DEVICES_H

#include <stdint.h>

#define PHONOLITE_DEVICES_INTERNAL __attribute__((visibility("hidden")))

// Discovery preserves CoreAudio enumeration order and includes alive output devices.
PHONOLITE_DEVICES_INTERNAL int32_t audio_output_devices_count(void);
PHONOLITE_DEVICES_INTERNAL uint32_t audio_output_devices_id(int32_t index);
// Name storage remains caller-owned. Returns zero on success, minus one on failure.
PHONOLITE_DEVICES_INTERNAL int32_t audio_output_devices_name(uint32_t device_id, char *buffer, int32_t buffer_length);

#undef PHONOLITE_DEVICES_INTERNAL

#endif
