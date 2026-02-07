#include "phonolite_opus.h"

#include <stdlib.h>

#include "opus.h"

struct PhonoliteOpusDecoder {
    OpusDecoder* decoder;
    int32_t sample_rate;
    int32_t channels;
};

PHONOLITE_OPUS_API PhonoliteOpusDecoder* phonolite_opus_decoder_create(
    int32_t sample_rate,
    int32_t channels,
    int32_t* error_out) {
    int err = OPUS_OK;
    OpusDecoder* decoder = opus_decoder_create(sample_rate, channels, &err);
    if (decoder == NULL || err != OPUS_OK) {
        if (error_out) {
            *error_out = err != OPUS_OK ? err : -1;
        }
        return NULL;
    }

    PhonoliteOpusDecoder* handle = (PhonoliteOpusDecoder*)malloc(sizeof(PhonoliteOpusDecoder));
    if (!handle) {
        opus_decoder_destroy(decoder);
        if (error_out) {
            *error_out = OPUS_ALLOC_FAIL;
        }
        return NULL;
    }

    handle->decoder = decoder;
    handle->sample_rate = sample_rate;
    handle->channels = channels;

    if (error_out) {
        *error_out = OPUS_OK;
    }

    return handle;
}

PHONOLITE_OPUS_API void phonolite_opus_decoder_destroy(
    PhonoliteOpusDecoder* decoder) {
    if (!decoder) {
        return;
    }
    if (decoder->decoder) {
        opus_decoder_destroy(decoder->decoder);
    }
    free(decoder);
}

PHONOLITE_OPUS_API int32_t phonolite_opus_decode(
    PhonoliteOpusDecoder* decoder,
    const uint8_t* data,
    int32_t len,
    int16_t* pcm,
    int32_t frame_size) {
    if (!decoder || !decoder->decoder || !data || len <= 0 || !pcm || frame_size <= 0) {
        return OPUS_BAD_ARG;
    }

    return opus_decode(decoder->decoder, data, len, pcm, frame_size, 0);
}

PHONOLITE_OPUS_API int32_t phonolite_opus_max_frame_size(void) {
    return 5760;
}
