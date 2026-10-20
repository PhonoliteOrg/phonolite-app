# Audio playback profiles

For actual visible playbar taps and HQ/MQ/LQ checks, see
[Visible playbar controls and streaming quality](PLAYER_CONTROLS.md).

These opt-in physical-device tests play real audio through the production
controller, QUIC receiver, cache, decoder, worker and native output. The test-only
root uses `AppController.audioEngineFactory` to observe the existing callbacks;
there are no changes to `lib/`, native output code, production assets or packages.
The usual UI suite still avoids starting playback.

```sh
bash tools/ui_tests/run_audio_profile.sh DEVICE_ID
# Longer streaming observation, without a second timeline recorder:
bash tools/ui_tests/run_audio_profile.sh DEVICE_ID \
  --dart-define=AUDIO_MODE=stream --dart-define=AUDIO_SECONDS=120
```

Keep the unlocked phone in the foreground with its normal output selected. This
starts audible playback, uses the stored login, and stops playback in cleanup.
It leaves the app installed, preserving data and Local Network permission.
Playback may contribute to the app's ordinary listening history. No new downloads,
likes, playlists, volume settings or output routes are created/changed.
An existing playing queue is replaced; it is not restored afterward.

| Scenario | What is checked |
| --- | --- |
| `audio.stream_start_and_ui_load` | Start a server album track; observe 30 seconds while navigating Library, Playlists, Liked and Settings |
| `audio.pause` | After a callback grace period, native output position remains still for a three-second pause |
| `audio.resume` | Native output resumes and continues for eight seconds |
| `audio.seek_forward` / `audio.seek_backward` | Output reaches the requested position range and then progresses for eight seconds |
| `audio.next_track` | Queue changes to another track which produces native output |
| `audio.local_playback` | An existing downloaded track plays through the local decoder and native output for twelve seconds |

These are controller-level audio scenarios with real UI activity. They do not
claim that Play/Pause/Next/seek gestures have been covered in the UI inventory.
They do not change shuffle/repeat preferences. Local playback is skipped if no
download of at least twenty seconds exists. Streaming needs a signed-in session
and an album with a track at least `AUDIO_SECONDS + 60` seconds long, followed by
another track of at least fifteen seconds. Discovery checks a bounded portion of
the catalog; use `AUDIO_ALBUM_ID` to select a particular album. Missing
prerequisites are explicit skips; a run with no verified scenarios fails.

## Metrics and default checks

| Metric | Meaning / default check |
| --- | --- |
| `first_output_progress_ms` | Monotonic request-to-first native completed-buffer progress; at most 3000 ms. Includes the engine's 250 ms sampling and output-buffer completion delay; an upper-bound proxy for first sound |
| `rendered_to_wall_ratio` | Native output position delta / wall delta after first progress; at least 0.95 and at most 1.10. The upper bound catches accidental position jumps |
| `stall_count`, `observed_stall_ms` | Output has not advanced for at least 750 ms, including a stall at the end of the observation; zero expected. Quantized by engine reporting; not an exact duration of audible silence |
| `rebuffer_count` | Number of production `Buffer low:` events in the phase; zero expected |
| `engine_error_count` | Categorized output/playback/worker errors; zero expected |
| `pause_drift_ms` | Position range after allowing 750 ms for a callback already in flight; at most 100 ms |
| `steady_max_telemetry_gap_ms` | More than 1000 ms, or fewer than eight samples, makes the measurement insufficient and fails the scenario |
| `min_buffered_ahead_ms` | Diagnostic only; remote values include encoded cache and are not native PCM queue depth |
| `native_underrun_count` | `null`: the current native backend exposes no underrun counter |

Latency and startup are separate from steady playback. Pause and seek have their
own phases, so intentional discontinuities do not count as streaming stalls.
The metrics use the engine's actual completed-buffer position, rather than the
player's animated/scrub-preview position. At least two seconds of steady progress
is required. A timer/callback gap can be app scheduling rather than audio loss;
insufficient telemetry is never presented as proof of smooth playback.

The source might contain intentional silence, and successful output callbacks do
not prove that a speaker/headphone emitted the right waveform. No microphone or
loopback capture is used. Distortion, clicks, route/volume problems, and dropouts
shorter than the detection window still need listening or acoustic capture.
Background/lock-screen playback, route changes, interruptions, cellular handoffs,
injected network loss, track completion/automatic advance, and every codec/server
mode are not exercised by these initial device scenarios.

## Options and reports

- `AUDIO_MODE=all|stream|local` (default `all`)
- `AUDIO_SECONDS=8..300` (default `30`, sustained stream phase only)
- `AUDIO_ALBUM_ID=...` (optional server album fixture)
- `AUDIO_LATENCY_BUDGET_MS=3000`
- `AUDIO_STALL_MS=750` (minimum `500`)
- `UI_CAPTURE_TIMELINE=false` to repeat without tracing overhead
- Shell `UI_REPORT_DIR` to change the default `build/audio-profile` destination

`build/audio-profile/latest.txt` points to the latest run. `REPORT.md` summarizes
results; `run.json` contains machine-readable summaries and unrun scenarios.
Each `.audio.json` contains raw timestamped observations and categorized events;
`.frames.json` and `.timeline.json` contain the concurrent UI measurements.
The host saves results incrementally, including failures/skips. Raw events omit
engine message text, file paths and credentials. VM traces may still contain
application arguments; review before sharing. Do not start a second timeline
capture via MCP while this driver records one. MCP CPU sampling is independent.

After the suite, restore the regular entry point:

```sh
flutter run --profile --no-dds --target lib/main.dart -d DEVICE_ID
```

Metric regression tests and synthetic failure examples are in
[`../../test/audio_automation/`](../../test/audio_automation/). Existing
`test/architecture/streaming_*`, `audio_worker_recovery_test.dart`, and
`local_playback_native_test.dart` cover engine behavior with host adapters;
they are not substitutes for real-device output observations.
