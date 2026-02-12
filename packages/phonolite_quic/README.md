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
