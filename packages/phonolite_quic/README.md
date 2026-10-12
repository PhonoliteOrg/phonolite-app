# phonolite_quic

Rust QUIC client FFI library for the Phonolite Flutter app.

## Build Requirements
1. Rust toolchain (`rustup`, `cargo`).
2. Android: `cargo-ndk` and the Android NDK.
3. iOS/macOS: Xcode command line tools (for `lipo`/`xcrun`).

## Notes
1. iOS/macOS CocoaPods runs `build_quic_static.sh` to produce `libphonolite_quic.a`.
2. Android Gradle invokes `cargo ndk` to populate `src/main/jniLibs`.
3. Windows/Linux CMake invokes `cargo build` and bundles the resulting library.

## Audio delivery
`openTrack(startMs: ...)` and `seek()` return a generation echoed by the server
as `request_id`. Each seek invalidates pending native bytes immediately, then
selects a fresh unidirectional stream. `pollEvent()` exposes stream acknowledgments
and errors independently of audio reads, including range boundaries and the
source version used by the app's encoded cache.

Native delivery holds at most 512 KiB. When full, it leaves active audio inside
QUIC's flow-control window while continuing to process control messages. Short
FFI reads retain the remainder for the next read. `suspendAudio()` cancels active
delivery when the app serves a cached range; the next open or seek resumes it.

Keepalive pings run every 10 seconds. Unsent buffer/playback telemetry is
coalesced. Rebuild the native library together with the Dart package whenever
these FFI APIs change.
