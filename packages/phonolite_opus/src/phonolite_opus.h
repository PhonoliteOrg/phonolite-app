#ifndef PHONOLITE_OPUS_H
#define PHONOLITE_OPUS_H

#include <stdint.h>

#if defined(_WIN32)
  #define PHONOLITE_OPUS_API __declspec(dllexport)
#else
  #define PHONOLITE_OPUS_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct PhonoliteOpusDecoder PhonoliteOpusDecoder;

PHONOLITE_OPUS_API PhonoliteOpusDecoder* phonolite_opus_decoder_create(
    int32_t sample_rate,
    int32_t channels,
    int32_t* error_out);

PHONOLITE_OPUS_API void phonolite_opus_decoder_destroy(
    PhonoliteOpusDecoder* decoder);

PHONOLITE_OPUS_API int32_t phonolite_opus_decode(
    PhonoliteOpusDecoder* decoder,
    const uint8_t* data,
    int32_t len,
    int16_t* pcm,
    int32_t frame_size);

PHONOLITE_OPUS_API int32_t phonolite_opus_max_frame_size(void);

#ifdef __cplusplus
}
#endif

#endif
