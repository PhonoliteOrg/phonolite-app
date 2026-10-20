# Interaction and state coverage

The temporary HTTP-server suite, its certificates/audio fixtures, dependent
device cases and launchers have been removed at the user's request. The results
below are historical evidence from that testing pass, not currently runnable
coverage. Ordinary UI profiling, real-server audio/player tests, guarded live
account tests and host regression tests remain available.

The [catalog](catalog/INTERACTIONS.md) contains 241 source-audited patterns,
including desktop controls, native system UI, source-only pages and unwired
callbacks. Pattern counts do not enumerate every input or state combination.
[The generated device audit](../build/isolated-profile/COVERAGE_AUDIT.md) keeps
live-account evidence separate from on-device disposable fixtures. Only passed
journeys count; saved passes from interrupted runs remain individual evidence.
At the end of the testing pass, the union was **218/241** patterns: 76 had live-device
evidence and 208 have isolated device evidence, with overlap. This is cumulative
evidence across multiple runs, including targeted verification after fixes.

## Device matrix

| Area | Evidence | Limits / remaining work |
| --- | --- | --- |
| Navigation | Connected and disconnected ordered tab pairs, retained artist/album routes, actual iOS interactive edge-back | Gesture verification is for the tested iPhone layout |
| Artist / album | Local/server details, release layouts and contributions, scrolling, long-press selection, all/none, removal cancellation | Desktop Read more / Collapse is absent from compact phone headers |
| Playlists | Local/server create, rename, membership remove/cancel/re-add, selection and deletion; local download copy and selected download removal | Native image selection needs a manual/native UI run; fixture mutations do not certify server authorization |
| Downloads | Real loopback TLS, production download worker, FLAC bytes and integrity checks; pause/resume/cancel/retry and deletion cases | Private custom storage selects the production inline core. Timings do not benchmark the normal actor configuration or real WAN bandwidth |
| Player | Prior live HQ/MQ/LQ transport/quality/button runs; native local controls; all 12 local/server shuffle mode combinations advance the queue and check the resulting source; overflowing mini-player tags scroll in both directions | No acoustic recording; no exact underrun counter or certification of every codec/input/network condition |
| Connection loss | Actual loopback HTTPS socket closure/recovery and visible Retry; sign-out while native local output continues | The source QUIC connection is separate. This does not reproduce Wi-Fi/cellular loss or a QUIC network interruption |
| Authentication | Real phone form validation, checking/reachable/offline/authenticated views, fixture password submit/success and session retention | OPAQUE authentication/password changes against the actual server require the separate disposable-account suite |
| Statistics | Populated rankings, artist/track links, month/year controls, refresh, local import, collection toggle, fixture reset | Actual account deletion requires a disposable account; fixture responses do not validate the deployed server protocol |
| Settings / logs | Server menu, shuffle artist/genre controls, all/clear, category filters, clipboard, selection and reset flows | Per-case reports record failures/skips; desktop storage-path controls are intentionally hidden on iOS |
| Empty state / reset | Confirmed full reset of private fixture downloads/playlists and cleanup verification | The normal app's files and credential vault are not the target of these resets |
| Output / system UI | Output picker, refresh and System Default in prior live runs | No alternate output hardware was available. Bluetooth/AirPlay, system volume, permission sheets and photo pickers remain native/manual coverage |
| Desktop | Widget coverage for wide layouts, storage forms, shortcuts, volume and navigation | No physical desktop performance claim in the phone matrix |

## What runs where

- [Safe default journeys](journeys/all_journeys.dart) reuse the normal saved app
  data and discard drafts.
- [Live account mutations](live_account_profile_test.dart) use the actual server,
  private client storage and an exact user-confirmed disposable username guard.
  Passwords are entered privately into the phone's real keyboard/form. This
  suite is never included in another run automatically.

Run commands, case selection and report formats are in [README.md](README.md).
Historical fixture reports remain under `build/isolated-profile/`, with their
original environment labels. The read-only audit tool still distinguishes
those archived results from live-server evidence.

## Findings and verification

This pass removes animation-controller allocations from untouched idle track
rows, fixes drag-to-dismiss for short Library search results, forwards composite
snapshots for custom-storage download/library updates, and distinguishes
server-declined audio requests from transport failures. The source rejection
path stops playback without a reconnect loop; transport failures retain their
recovery behavior. The negative-path device journey also attempts a valid track
afterward. The final native rebuild passed that rejection/recovery case, download
job controls/retry/removal, logs actions, disconnected local audio, and edge-back
in [the focused device report](../build/isolated-profile/2026-10-20T02-51-27.946716Z/REPORT.md).
The custom-storage snapshot fix applies to the inline configuration; the default
download actor is unchanged.

One source catalog track, A-Ha's “2 - Train of Thought (2015 Remaster)” on
*Hunting High and Low*, reports duration 0 and is rejected by the real server.
[The finding](../build/isolated-profile/SERVER_FINDINGS.md) identifies it.
The removed positive-playback fixtures excluded zero-duration entries; the
archived rejection/recovery result retains the rejected-track evidence.
This does not repair the server's media metadata.

Frame build/raster p95, individual slow frames, native output progress, skips and
failures are recorded per journey. Native audio progress cannot establish what
came out of the speaker or exclude dropouts shorter than the metric threshold.
The heap inspection supports an allocation improvement, not a measured FPS gain.

The CPU-sampled liked-download workload still exceeded the 120Hz frame budget
on 9.18% of its frames (build p95 8.63ms, raster p95 6.40ms). Its 747 CPU samples
include Flutter rendering, test bindings, finder traversal and the loopback
download backend alongside app work. The fixture uses custom-storage inline
downloads, so this result does not establish a default-actor bottleneck or a
matched before/after gain. See [the diagnostic](../build/isolated-profile/liked_download_cpu_finding.json).

Host validation passed 488 visible widget/harness checks, 78 audio lifecycle and
worker checks, 70 focused offline checks, and 15 native QUIC tests. These suites
overlap; their counts are not a unique-test total. Wider source analysis still
reports preexisting Windows constant-name style infos and a download-core
unawaited-return warning. [Validation details](../build/isolated-profile/VALIDATION.json)
record the exact logs and remaining live-account/hardware work.
