#import <Foundation/Foundation.h>

extern void *phonolite_opus_decoder_create(int32_t sample_rate, int32_t channels, int32_t *error_out);
extern void phonolite_opus_decoder_destroy(void *decoder);
extern int32_t phonolite_opus_decode(
    void *decoder,
    const uint8_t *data,
    int32_t len,
    int16_t *pcm,
    int32_t frame_size);
extern int32_t phonolite_opus_max_frame_size(void);

extern void *phonolite_audio_open(int32_t sample_rate, int32_t channels, int32_t device_id);
extern void phonolite_audio_close(void *player);
extern int32_t phonolite_audio_write(void *player, const int16_t *samples, int32_t sample_count);
extern void phonolite_audio_set_volume(void *player, float volume);
extern void phonolite_audio_pause(void *player);
extern void phonolite_audio_resume(void *player);
extern int64_t phonolite_audio_collect_done_samples(void *player);
extern int32_t phonolite_audio_is_idle(void *player);
extern int32_t phonolite_audio_get_output_device_count(void);
extern uint32_t phonolite_audio_get_output_device_id(int32_t index);
extern int32_t phonolite_audio_get_output_device_name(
    uint32_t device_id,
    char *buffer,
    int32_t buffer_len);

__attribute__((used)) static void *phonolite_opus_keep_symbols[] = {
  (void *)phonolite_opus_decoder_create,
  (void *)phonolite_opus_decoder_destroy,
  (void *)phonolite_opus_decode,
  (void *)phonolite_opus_max_frame_size,
  (void *)phonolite_audio_open,
  (void *)phonolite_audio_close,
  (void *)phonolite_audio_write,
  (void *)phonolite_audio_set_volume,
  (void *)phonolite_audio_pause,
  (void *)phonolite_audio_resume,
  (void *)phonolite_audio_collect_done_samples,
  (void *)phonolite_audio_is_idle,
  (void *)phonolite_audio_get_output_device_count,
  (void *)phonolite_audio_get_output_device_id,
  (void *)phonolite_audio_get_output_device_name,
};
