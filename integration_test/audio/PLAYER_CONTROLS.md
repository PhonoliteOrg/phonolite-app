# Visible playbar controls and streaming quality

```sh
bash tools/ui_tests/run_player_controls.sh DEVICE_ID
```

The separate `player_controls_profile_test.dart` entry point launches the real
HomePage/controller/native audio in profile mode. The compact and expanded
controls are tapped through Flutter's hit testing; the controller is used for
fixture setup and restoration. It plays real audio and replaces the current
queue. It requires an unlocked foreground phone, a restored server login, and an
album with a three-minute track followed by another track of at least thirty
seconds. `AUDIO_ALBUM_ID` selects a particular fixture if discovery finds none.

| Control | Verification |
| --- | --- |
| Compact Pause / Play | Engine pause/resume command plus stopped/resumed native sample progress |
| Compact Next / expanded Previous | Correct queue track changes and new native output |
| Compact body | Expanded tray opens |
| Expanded Pause / Play | Native output and expected state |
| Progress slider | Real pointer taps commit forward/backward engine seeks and output reaches the requested position |
| HQ / MQ / LQ | UI selection, exact fixed-quality/20 ms engine request and native playback progress |
| Quality while paused | Selection preserves pause; subsequent resume uses that quality |
| Repeat | UI/controller state and server setting toggle, then restore |
| Shuffle | Current Album and Off selections |
| Volume | Pointer changes reach the real engine where the layout exposes a slider; the native mobile tray uses system volume and is reported as skipped |
| Like | Real server like state toggles and returns to the original state |
| Playlist-add | Opens chooser, filters it, adds the track to an isolated temporary playlist, verifies server membership, deletes the playlist |
| Output | Opens, refreshes and selects the available current output |
| Artwork/details | Opens the playing album |
| Swipe dismissal | Returns to compact player and keeps playing |
| Stop | Track clears and idle transport buttons remain disabled |

Output selection on iOS exposes System Default through the existing backend.
Bluetooth/AirPlay changes and other hardware routes are not fabricated by this
suite. Shuffle scope/options that need downloads, configured custom rules or a
playlist queue need their own data scenarios. Existing widget tests cover source
switching and disabled/enabled shuffle options at compact and wide sizes.

## Encoded qualities

The chooser also offers **Original (source bitrate)**, abbreviated **OG**. This
streams the unchanged source file through the native PCM32 decode/output path;
it has no fixed target bitrate. See [Original audio playback](../../docs/original-audio-playback.md)
for precision, platform constraints and the separate headless verification.
The HQ/MQ/LQ measurements below continue to cover the compressed profiles.

The server defines fixed HQ/MQ/LQ targets as 160000 / 96000 / 48000 bits/s.
After playback stops, independent requests use the production QUIC library and
the same track's ten-second offset. Each parses a real Opus header and two seconds
of encoded packets. The header's target, 48000 Hz sample rate, 20 ms frames and
channel count are checked. Encoded bytes divided by **media duration** produce a
payload bitrate; HQ > MQ > LQ is checked for that same source interval. Network
download bursts are not treated as codec bitrate. Opus variable bitrate can
differ from its declared target.

These requests are separate from the app playback connection. The UI cases
independently verify the exact settings handed to the real engine and native
output continuity. This combination checks request routing, server profiles and
playability without adding instrumentation to the shipping audio pipeline.
Auto exists internally but is not offered in the visible quality chooser.

Changing quality while paused now restarts the active stream with the new
settings while keeping its paused state. A quality change also bypasses the
same-track/position duplicate-start guard; selecting the current quality is a
no-op. Focused regressions are in
`test/architecture/controller_lifecycle_test.dart` (search “quality”).

## Results and restoration

`build/player-controls/latest.txt` points to the latest run. `REPORT.md` includes
each scenario, observed control effects and encoded quality samples. `run.json`
and individual `.audio.json`/`.frames.json` files contain machine-readable results.
The driver saves incrementally; failures and unrun scenarios remain visible.
Timeline capture defaults off to reduce observer overhead.

Likes, volume, repeat and shuffle settings are restored. A temporary playlist is
removed even when an assertion fails, and cleanup errors fail the run. Playback
is stopped; the previous queue is not restored. Ordinary listening history may
include test playback. As with the [audio continuity suite](README.md), native
output telemetry does not establish acoustic quality or rule out short clicks.
The ordinary UI suite still avoids starting playback.

Restore the regular app afterward with:

```sh
flutter run --profile --no-dds -t lib/main.dart -d DEVICE_ID
```

The test target also registers `ext.phonolite.inspectQuality` for independent
diagnostic repeats without rebuilding. While its VM service is connected, use
`dart run tools/ui_tests/inspect_quality.dart WS_URI high 2000 10000`.
This reports incomplete samples, received bytes and stream-range announcements.
It does not register in the ordinary app. Packet probes refresh buffer feedback
and follow range continuations rather than treating a bounded range as full-track
completion.

`dart run tools/ui_tests/inspect_live_audio.dart WS_URI OUTPUT_JSON` is a
read-only alternative for an already playing normal profile build. It inspects
the active worker's current encoded segment/header and up to 100 packet lengths
through the VM service, without opening a second stream. It returns unavailable
when no remote segment is active. A one-off live HQ inspection in the validation
run confirmed a 160000 bps header and approximately 161.4 kbps of encoded payload.
