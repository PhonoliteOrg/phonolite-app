#ifndef PHONOLITE_TEST_AUDIO_TOOLBOX_H
#define PHONOLITE_TEST_AUDIO_TOOLBOX_H

#include <stdbool.h>
#include <stdint.h>

/* Device-free declarations for the AudioQueue contract used by the real backend. */
typedef int32_t OSStatus;
typedef uint32_t UInt32;
typedef bool Boolean;
typedef struct TestAudioQueue *AudioQueueRef;
typedef void *AudioQueueTimelineRef;
typedef struct TestAudioBuffer {
  void *mAudioData;
  UInt32 mAudioDataByteSize;
} *AudioQueueBufferRef;
typedef struct AudioTimeStamp {
  double mSampleTime;
  UInt32 mFlags;
} AudioTimeStamp;
typedef struct AudioStreamBasicDescription {
  double mSampleRate;
  UInt32 mFormatID, mFormatFlags, mBytesPerPacket, mFramesPerPacket;
  UInt32 mBytesPerFrame, mChannelsPerFrame, mBitsPerChannel;
} AudioStreamBasicDescription;
typedef void (*AudioQueueOutputCallback)(void *, AudioQueueRef, AudioQueueBufferRef);

enum {
  noErr = 0,
  kAudioQueueErr_InvalidRunState = -66678,
  kAudioTimeStampSampleTimeValid = 1,
  kAudioFormatLinearPCM = 2,
  kLinearPCMFormatFlagIsSignedInteger = 4,
  kLinearPCMFormatFlagIsPacked = 8,
  kAudioQueueProperty_CurrentDevice = 16,
  kAudioQueueParam_Volume = 32
};

OSStatus AudioQueueNewOutput(const AudioStreamBasicDescription *, AudioQueueOutputCallback,
                            void *, void *, void *, UInt32, AudioQueueRef *);
OSStatus AudioQueueCreateTimeline(AudioQueueRef, AudioQueueTimelineRef *);
OSStatus AudioQueueDisposeTimeline(AudioQueueRef, AudioQueueTimelineRef);
OSStatus AudioQueueGetCurrentTime(AudioQueueRef, AudioQueueTimelineRef, AudioTimeStamp *, Boolean *);
OSStatus AudioQueueStart(AudioQueueRef, const AudioTimeStamp *);
OSStatus AudioQueuePause(AudioQueueRef);
OSStatus AudioQueueReset(AudioQueueRef);
OSStatus AudioQueueStop(AudioQueueRef, Boolean);
OSStatus AudioQueueDispose(AudioQueueRef, Boolean);
OSStatus AudioQueueAllocateBuffer(AudioQueueRef, UInt32, AudioQueueBufferRef *);
OSStatus AudioQueueFreeBuffer(AudioQueueRef, AudioQueueBufferRef);
OSStatus AudioQueueEnqueueBufferWithParameters(AudioQueueRef, AudioQueueBufferRef, UInt32,
    const void *, UInt32, UInt32, UInt32, const void *, const AudioTimeStamp *, AudioTimeStamp *);
OSStatus AudioQueueSetProperty(AudioQueueRef, UInt32, const void *, UInt32);
OSStatus AudioQueueSetParameter(AudioQueueRef, UInt32, float);

#endif
