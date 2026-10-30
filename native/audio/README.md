# AudioQueue progress verification

The iOS and macOS backends use `audio_queue_progress.h` to count rendered
interleaved PCM samples from the queue's sample clock. AudioQueue callbacks
release buffer storage; they do not establish that playback has finished.

`audio_queue_progress_test.c` checks the portable sample accounting.
`audio_queue_player_test.c` compiles the actual macOS backend against the small
fake AudioQueue API in `test_support/`. It verifies early callbacks (including
inside enqueue), delayed hardware time, partial drain, pause/resume, seek/reset
generations, and clock-discontinuity errors. The fake is synchronous and does
not exercise Apple frameworks or concurrent callbacks.

From the app directory on a C11 compiler:

```sh
cc -std=c11 native/audio/audio_queue_progress_test.c -lm -o /tmp/audio_queue_progress_test
/tmp/audio_queue_progress_test
cc -std=c11 -Inative/audio/test_support native/audio/audio_queue_player_test.c macos/Runner/Infrastructure/Audio/Native/audio_queue_player.c -lm -o /tmp/audio_queue_player_test
/tmp/audio_queue_player_test
```

MSVC can compile the same tests with `/std:c17 /experimental:c11atomics`.
Force-include the absolute path to `test_support/compiler.h` for the backend
test to omit the Apple visibility attribute. Use a developer command prompt
with the MSVC and Windows SDK include/library paths configured.

These tests open no audio device. An Apple SDK build and the Runner XCTest
suite remain necessary to verify framework integration on an Apple host.
