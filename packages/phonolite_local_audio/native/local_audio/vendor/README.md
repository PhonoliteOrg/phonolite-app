# Symphonia FLAC seek correction

`symphonia-bundle-flac/` contains the six Rust source files, Cargo manifest,
README, and MPL 2.0 license for **symphonia-bundle-flac 0.5.5**. Source was copied
from the published crates.io package. Its recorded upstream revision is
[`6d533f26150953a882a6a111ebd13f0abf7129d5`](https://github.com/pdeljanov/Symphonia/tree/6d533f26150953a882a6a111ebd13f0abf7129d5/symphonia-bundle-flac).
The license is copied from that revision's repository root. Original copyright
and license notices remain in each source file; see
[LICENSE](symphonia-bundle-flac/LICENSE).

The only behavior change is in `src/demuxer.rs`: when the FLAC seek binary
search places its midpoint inside the final frame, a forward resynchronization
can reach EOF even though the requested sample exists. The patched search
reduces its upper byte bound and retries instead of propagating that EOF.
Other errors still propagate. The existing search and final packet scan remain
in use; source lengths and source bytes are unchanged, and no whole-track
decode is introduced.

The decoder package selects this copy through `[patch.crates-io]`. Its native
regression `seeks_within_a_large_32bit_flac_frame_after_eof` uses a generated
192 kHz, 32-bit, single-frame FLAC whose encoded frame exceeds the upstream
binary-search threshold. It checks seeking after EOF, seeking back to zero,
starting at an offset, and exact retained samples.

Remove this patch when the selected upstream release includes the correction,
after rerunning that regression and the Original playback integration tests.
