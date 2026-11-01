#import <Foundation/Foundation.h>

#include "../../src/phonolite_opus.h"

__attribute__((used)) static void *phonolite_opus_keep_symbols[] = {
  (void *)phonolite_opus_decoder_create,
  (void *)phonolite_opus_decoder_destroy,
  (void *)phonolite_opus_decode,
  (void *)phonolite_opus_max_frame_size,
};
