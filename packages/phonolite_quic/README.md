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

Original source streaming uses a separate 4 MiB byte queue and pins its source
version and total length. An established source retries a transient connection
failure once at the unreturned byte offset within the existing read deadline,
preserving the decoder and its buffered PCM. Cancellation, certificate/pin
failures and source rejection bypass that retry. A reconnect must verify the
same server pin and source representation before returning further bytes.

Route changes are signaled separately from seek/cancellation through the owner
lease. Original recovery shares one fifteen-second episode and three connection
attempts; native read/seek budgets remain five seconds. Source metadata and the
remaining episode budget can be transferred to a fresh decoder after an escaped
read failure. Rebuild both native audio libraries with the Dart bindings and C
headers when these APIs change.

QUIC migration defaults off. Build the app with
`--dart-define=PHONOLITE_QUIC_MIGRATION=true` and enable the server's
`quic_allow_client_migration` setting to opt in after platform validation.
`notifyNetworkChange()` reports whether a migration was queued. `pollEvent()`
reports validated paths or `transport_recovery` when buffered reconnect is
required. The client verifies handshake confirmation, identity, peer permission
and spare IDs, preserves source/destination address and pacing metadata, and
bounds path validation to one second. It activates a validated path with a
non-probing packet so receive-only audio does not wait for the next keepalive.
Migration changes the client's route to the same server; it does not select an
alternate LAN/public server endpoint.
