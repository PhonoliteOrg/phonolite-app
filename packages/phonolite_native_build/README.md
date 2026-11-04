# Phonolite native build hooks

Shared macOS build-hook implementation for the Opus, local-audio and QUIC FFI
packages. Flutter compiles one code asset per target architecture, combines
Intel and Apple Silicon binaries, and bundles/signs the same framework names
used by the existing Dart library loaders.

Opus uses the checked-in CMake source. The Rust packages use locked Cargo
dependencies and their existing `cdylib` outputs. All builds honor Flutter's
target architecture and minimum macOS version and use the selected macOS SDK.
Unsupported architectures fail explicitly. Compilation and assets remain in the
hook output directories; source edits, including vendored Opus edits, invalidate
the hook cache.

Only macOS uses these hooks. Other platforms retain their current plugin build
integration. macOS no longer needs the three FFI CocoaPods build phases.
