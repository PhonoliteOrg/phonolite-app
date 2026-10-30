#include <AudioToolbox/AudioToolbox.h>
#include "../../macos/Runner/Infrastructure/Audio/Native/audio_queue_player.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

struct TestAudioQueue {
  AudioQueueOutputCallback callback;
  void *context;
  AudioQueueBufferRef pending[8];
  int pending_count;
  int bytes_per_frame;
  int starts;
  bool running;
  bool clock_valid;
  bool discontinuity;
  double frame;
  double scheduled_end;
};

static AudioQueueRef current_queue;
static int allocated_buffers;

static void acquire_buffers(AudioQueueRef queue) {
  while (queue->pending_count > 0) {
    AudioQueueBufferRef buffer = queue->pending[--queue->pending_count];
    queue->callback(queue->context, queue, buffer);
  }
}

OSStatus AudioQueueNewOutput(const AudioStreamBasicDescription *format, AudioQueueOutputCallback callback,
                            void *context, void *run_loop, void *mode, UInt32 flags, AudioQueueRef *output) {
  (void)run_loop; (void)mode; (void)flags;
  AudioQueueRef queue = calloc(1, sizeof(*queue));
  assert(queue != NULL);
  queue->callback = callback;
  queue->context = context;
  queue->bytes_per_frame = format->mBytesPerFrame;
  current_queue = *output = queue;
  return noErr;
}

OSStatus AudioQueueCreateTimeline(AudioQueueRef queue, AudioQueueTimelineRef *timeline) {
  *timeline = queue;
  return noErr;
}
OSStatus AudioQueueDisposeTimeline(AudioQueueRef queue, AudioQueueTimelineRef timeline) {
  assert(timeline == queue);
  return noErr;
}
OSStatus AudioQueueGetCurrentTime(AudioQueueRef queue, AudioQueueTimelineRef timeline,
                                AudioTimeStamp *time, Boolean *discontinuity) {
  assert(timeline == queue);
  time->mFlags = queue->clock_valid ? kAudioTimeStampSampleTimeValid : 0;
  time->mSampleTime = queue->frame;
  *discontinuity = queue->discontinuity;
  return noErr;
}
OSStatus AudioQueueStart(AudioQueueRef queue, const AudioTimeStamp *start) {
  (void)start;
  queue->starts++;
  queue->running = true;
  acquire_buffers(queue); /* Storage returns before any sample reaches the device. */
  return noErr;
}
OSStatus AudioQueuePause(AudioQueueRef queue) { queue->running = false; return noErr; }
OSStatus AudioQueueReset(AudioQueueRef queue) {
  acquire_buffers(queue);
  queue->frame = queue->scheduled_end = 5000;
  queue->clock_valid = queue->discontinuity = false;
  return noErr;
}
OSStatus AudioQueueStop(AudioQueueRef queue, Boolean immediate) {
  assert(immediate);
  queue->running = false;
  acquire_buffers(queue);
  return noErr;
}
OSStatus AudioQueueDispose(AudioQueueRef queue, Boolean immediate) {
  assert(immediate && queue->pending_count == 0);
  free(queue);
  current_queue = NULL;
  return noErr;
}
OSStatus AudioQueueAllocateBuffer(AudioQueueRef queue, UInt32 size, AudioQueueBufferRef *output) {
  (void)queue;
  AudioQueueBufferRef buffer = calloc(1, sizeof(*buffer));
  assert(buffer != NULL);
  buffer->mAudioData = malloc(size);
  assert(buffer->mAudioData != NULL);
  *output = buffer;
  allocated_buffers++;
  return noErr;
}
OSStatus AudioQueueFreeBuffer(AudioQueueRef queue, AudioQueueBufferRef buffer) {
  (void)queue;
  free(buffer->mAudioData);
  free(buffer);
  allocated_buffers--;
  return noErr;
}
OSStatus AudioQueueEnqueueBufferWithParameters(AudioQueueRef queue, AudioQueueBufferRef buffer,
    UInt32 descriptions, const void *packets, UInt32 trim_start, UInt32 trim_end, UInt32 event_count,
    const void *events, const AudioTimeStamp *start, AudioTimeStamp *actual_start) {
  (void)descriptions; (void)packets; (void)trim_start; (void)trim_end;
  (void)event_count; (void)events; (void)start;
  actual_start->mSampleTime = queue->scheduled_end;
  actual_start->mFlags = kAudioTimeStampSampleTimeValid;
  queue->scheduled_end += buffer->mAudioDataByteSize / queue->bytes_per_frame;
  assert(queue->pending_count < 8);
  queue->pending[queue->pending_count++] = buffer;
  if (queue->running) acquire_buffers(queue); /* Reenter before enqueue returns. */
  return noErr;
}
OSStatus AudioQueueSetProperty(AudioQueueRef queue, UInt32 key, const void *value, UInt32 size) {
  (void)queue; (void)key; (void)value; (void)size;
  return noErr;
}
OSStatus AudioQueueSetParameter(AudioQueueRef queue, UInt32 key, float value) {
  (void)queue; (void)key; (void)value;
  return noErr;
}

int main(void) {
  int32_t pcm[1920] = {0};
  PhonoliteAudioPlayer *player = audio_queue_player_open_format(48000, 2, -1, 32);
  assert(player != NULL);
  assert(audio_queue_player_write32(player, pcm, 1920) == 0);
  assert(allocated_buffers == 0); /* Callback returned storage, but playback has not begun. */
  assert(audio_queue_player_collect_done_samples(player) == 0);
  assert(audio_queue_player_is_idle(player) == 0);
  current_queue->clock_valid = true;
  current_queue->frame = 240;
  assert(audio_queue_player_collect_done_samples(player) == 480);
  assert(audio_queue_player_collect_done_samples(player) == 0);
  audio_queue_player_pause(player);
  audio_queue_player_resume(player);
  assert(current_queue->starts == 2); /* Resume spans even after all callbacks have fired. */
  current_queue->frame = 960;
  assert(audio_queue_player_collect_done_samples(player) == 1440);
  assert(audio_queue_player_is_idle(player) == 1);

  /* Exercise an early callback inside enqueue before the scheduled span is finalized. */
  assert(audio_queue_player_write32(player, pcm, 400) == 0);
  assert(allocated_buffers == 0);
  assert(audio_queue_player_is_idle(player) == 0);
  current_queue->frame = 1060;
  assert(audio_queue_player_collect_done_samples(player) == 200);
  assert(audio_queue_player_flush(player) == 0);
  assert(audio_queue_player_collect_done_samples(player) == 0);
  assert(audio_queue_player_is_idle(player) == 1);
  assert(audio_queue_player_write32(player, pcm, 400) == 0);
  assert(audio_queue_player_collect_done_samples(player) == 0);
  current_queue->clock_valid = true;
  current_queue->frame = 5100;
  assert(audio_queue_player_collect_done_samples(player) == 200);
  assert(audio_queue_player_is_idle(player) == 0);
  current_queue->discontinuity = true;
  assert(audio_queue_player_collect_done_samples(player) == -1);
  assert(audio_queue_player_is_idle(player) == -1);
  assert(audio_queue_player_flush(player) == 0);
  assert(audio_queue_player_collect_done_samples(player) == 0);
  assert(audio_queue_player_write32(player, pcm, 400) == 0);
  current_queue->clock_valid = true;
  current_queue->frame = 5100;
  assert(audio_queue_player_collect_done_samples(player) == 200);
  current_queue->discontinuity = true;
  assert(audio_queue_player_collect_done_samples(player) == -1);
  /* A latched output error must not bypass synchronous resource disposal. */
  audio_queue_player_close(player);
  assert(current_queue == NULL && allocated_buffers == 0);
  puts("AudioQueue callback, drain, resume, generation and clock-error tests passed.");
  return 0;
}
