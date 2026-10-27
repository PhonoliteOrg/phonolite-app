# Original audio playback

The stream-quality chooser offers Original (source bitrate), High quality
(160 kbps), Medium quality (96 kbps), and Low quality (48 kbps). The playback
badge abbreviates Original as OG. Original has no fixed bitrate target: it
delivers the library file unchanged. Original is the startup default on fresh
installs and subsequent app starts.

Original uses authenticated HTTPS byte ranges at
`/api/stream/:track_id/original`. It bypasses Opus transcoding and the server's
48 kHz/16-bit intermediate format. The native file decoder supports the library's
MP3 and FLAC formats, preserves the source sample rate, and converts decoded
samples into full-range, left-aligned signed 32-bit PCM without truncating
16/24/32-bit integer sources. Downloaded playback shares this precise decode path.
Lossy formats do not have an original integer PCM bit depth; their decoded
precision is retained in the 32-bit path.

The native decoder runs in a dedicated isolate owned by the playback session.
Range reads have bounded cache memory and request deadlines. Its owner-exit hook
and heartbeat lease retire it even if the audio worker is forcibly stopped.
Pauses retain their intent, seeks use the original container's timestamps and
byte ranges, and a quality switch restarts at the current position. Original
remains a remote source for recovery, artwork and playback state.

Every request validates the authenticated server's SPKI pin and certificate
validity before sending credentials. Redirects, malformed ranges, changed files
and unsupported source formats are rejected. Transport timeouts and retryable
server failures retain the existing recovery behavior. There is no automatic
fallback from Original to an Opus quality.

Windows, Apple and Android adapters accept the source rate and PCM32 samples.
Android 12 and later use signed PCM32. Earlier Android versions can preserve up
to 24 valid integer bits through float32 output; requests requiring more precision
are rejected explicitly. Because MP3 decoding uses the 32-bit path, Original MP3
also requires Android 12 or later under this strict precision policy. Mono and
stereo sources are supported; additional channels are rejected.

The operating-system mixer, audio route and hardware can still perform format
conversion. Original preserves the source through Phonolite's decoder and PCM
buffers; it does not promise exclusive or bit-perfect device output.

Verification is headless: native decoder tests cover exact 192 kHz/24-bit and
32-bit FLAC samples, range parsing and TLS identity checks; Dart tests cover
isolate transfer, startup offset, seeking, cleanup, quality selection and pause
intent. Native output contracts check PCM32 submission without opening a device.
Set `PHONOLITE_LOCAL_AUDIO_LIBRARY` to a newly compiled decoder library to enable
the native Dart tests. Live listening and device routing remain user-run checks.

## Verification on 2026-10-27

- The final focused Flutter batch passed all 102 tests, including Original and
  local playback, exact PCM32 samples, seek/pause/resume, output lifetime, modal
  labels, source contracts, module boundaries, Apple/Android architecture and
  interaction-catalog consistency. The controller regression for switching to
  Original while paused also passed.
- All 18 native decoder tests passed, with Clippy and native compilation clean.
  A minimal, licensed Symphonia FLAC demuxer patch fixes an upstream seek failure
  inside a large final 32-bit frame. Its provenance and regression are documented
  in [the vendor notes](../packages/phonolite_local_audio/native/local_audio/vendor/README.md).
- Server compilation and 26 listener-free delivery/source-contract tests passed.
- Windows native output contracts, eight Android JVM progress checks, Android
  production Kotlin compilation and 14 portable Apple C facade checks passed.
  Actual Apple framework compilation requires an Apple SDK.
- Dart analysis of application source and affected verification files passed.
- The final Windows debug application build passed, including native linking
  and the FLAC seek correction. The executable was not launched, and no compiler
  helper processes created during verification remained running afterward.

A broader architecture run reported two unrelated existing failures: the UI
boundary check rejects the desktop-window configuration imported by
`responsive_breakpoints.dart`, and the Windows runner registration check expects
the separately built XAudio DLL sources inside the executable's source list.
Those responsibilities were left unchanged by this feature.

No Phonolite application, server, audio device or network listener was started
during verification.
