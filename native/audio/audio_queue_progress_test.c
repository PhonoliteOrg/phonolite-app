#include "audio_queue_progress.h"

#include <assert.h>
#include <stdio.h>

int main(void) {
  PhonoliteAudioProgressSpan first = {7, 1920, 2, 0, 0.0, true};
  /* Storage may already have returned; that cannot mark the source consumed. */
  assert(phonolite_progress_collect(&first, 7, false, 960.0) == 0);
  assert(phonolite_progress_collect(&first, 7, true, 0.0) == 0);
  assert(phonolite_progress_pending(&first, 7));
  assert(phonolite_progress_collect(&first, 7, true, 240.75) == 480);
  assert(phonolite_progress_collect(&first, 7, true, 240.75) == 0);
  assert(phonolite_progress_collect(&first, 7, true, 100.0) == 0);
  assert(phonolite_progress_collect(&first, 7, true, 960.0) == 1440);
  assert(!phonolite_progress_pending(&first, 7));

  /* A clock gap or route latency before the next buffer is not music. */
  PhonoliteAudioProgressSpan second = {7, 1920, 2, 0, 1440.0, true};
  assert(phonolite_progress_collect(&second, 7, true, 1200.0) == 0);
  assert(phonolite_progress_collect(&second, 7, true, 1440.0) == 0);
  assert(phonolite_progress_collect(&second, 7, true, 1680.0) == 480);
  assert(phonolite_progress_pending(&second, 7));

  /* Reset/seek generations cannot inherit old playback or callback credits. */
  assert(phonolite_progress_collect(&second, 8, true, 2400.0) == 0);
  assert(!phonolite_progress_pending(&second, 8));
  PhonoliteAudioProgressSpan replacement = {8, 400, 1, 0, 9000.0, true};
  assert(phonolite_progress_collect(&replacement, 8, true, 9200.0) == 200);
  assert(phonolite_progress_collect(&replacement, 8, true, 9400.0) == 200);
  assert(!phonolite_progress_pending(&replacement, 8));
  puts("AudioQueue clock progress tests passed.");
  return 0;
}
