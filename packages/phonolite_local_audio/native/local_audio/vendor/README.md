# Symphonia FLAC seek correction

`symphonia-bundle-flac/` contains the six Rust source files, Cargo manifest,
README, and MPL 2.0 license for **symphonia-bundle-flac 0.5.5**. Source was copied
from the published crates.io package. Its recorded upstream revision is
[`6d533f26150953a882a6a111ebd13f0abf7129d5`](https://github.com/pdeljanov/Symphonia/tree/6d533f26150953a882a6a111ebd13f0abf7129d5/symphonia-bundle-flac).
The license is copied from that revision's repository root. Original copyright
and license notices remain in each source file; see
[LICENSE](symphonia-bundle-flac/LICENSE).

The seek correction in `src/demuxer.rs` handles when the FLAC seek binary
search places its midpoint inside the final frame, a forward resynchronization
can reach EOF even though the requested sample exists. The patched search
reduces its upper byte bound and retries instead of propagating that EOF.
Other errors still propagate. The existing search and final packet scan remain
in use; source lengths and source bytes are unchanged, and no whole-track
decode is introduced.

The parser also discards buffered frame fragments before a seek. Without this
reset, a decoder that has read ahead to EOF can emit a stale final frame after
seeking into an earlier frame. `multi_frame_flac_repeated_seeks_after_read_ahead_eof_preserve_every_sample`
checks repeated seeks against the exact uninterrupted PCM suffix.

The decoder package selects this copy through `[patch.crates-io]`. Its native
regression `seeks_within_a_large_32bit_flac_frame_after_eof` uses a generated
192 kHz, 32-bit, single-frame FLAC whose encoded frame exceeds the upstream
binary-search threshold. It checks seeking after EOF, seeking back to zero,
starting at an offset, and exact retained samples.

Remove this patch when the selected upstream release includes the correction,
after rerunning that regression and the Original playback integration tests.

## Ogg Opus presentation timing

`symphonia-format-ogg/` contains the source, manifest, and MPL 2.0 license of
Symphonia's Ogg demuxer 0.5.5, with the same presentation-timing correction used
by Phonolite's server. It is copied into this package so local playback builds
independently of the server checkout. Its upstream origin and precise changes
are documented in [the vendor notes](symphonia-format-ogg/README.md).

The patch preserves OpusHead pre-skip, subtracts it from presentation timestamps,
and computes the exact tail trim even when the entire audio is on one Ogg page.
For a single-page Vorbis stream, the final granule also trims the tail rather
than shifting it into a leading delay; the buffered page is stamped again once
that trim is known. Repeated Vorbis/AAC seeks recreate the codec and decode a
bounded one-second pre-roll before retaining the requested PCM suffix.
The native decoder uses this timing with a bundled libopus adapter, retaining
float decode precision through the existing PCM32 interface. Tests cover every
download bitrate, mono/stereo, short tails, output gain, seeking, and corrupt or
truncated final pages. Its one-second seek pre-roll is bounded and also meets
Opus's minimum pre-roll requirement.

The native build compiles the existing `phonolite_opus/third_party/opus` sources
through Cargo/CMake. The package explicitly depends on `phonolite_opus`; it does
not require an installed Opus DLL or a server checkout. Windows/Linux dependency
tracking, Android NDK configuration, and the Apple static builds all use that
same source dependency.

## MP4 presentation edits

`symphonia-format-isomp4/` contains the MPL 2.0 demuxer 0.5.5 with the same
presentation edit patch as the server. It removes declared AAC priming and
padding, supports lossless unit-rate ALAC edits, and maps seeks into the audible
timeline. Unsupported edit patterns fail explicitly. See its [vendor notes](symphonia-format-isomp4/README.md).
