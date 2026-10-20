# On-screen interaction tests

Start with [the interaction inventory](catalog/INTERACTIONS.md). Each entry has a
stable ID, visible action, expected result, availability, effect, and implemented
device journeys. The feature JSON files in `catalog/` are the editable source.
[The source index](catalog/SOURCE_INDEX.md) lists candidate callback bindings to
help review gaps after UI changes; reusable wrappers are included.

This is an inventory of interaction **patterns**, not a claim to have visited
every runtime state. One track-row pattern covers repeated rows; local/server,
loading/disabled, empty/populated, and different layouts still need device runs.
Source-only SearchPage/SplashPage, desktop-only input, and native iOS UI are
explicitly distinguished from reachable mobile Flutter controls.

## Find a test

| Feature | Journey implementation | Examples |
| --- | --- | --- |
| Navigation | [navigation/](journeys/navigation/navigation_journeys.dart) | Primary tabs, optional Stats, all ordered tab pairs |
| Library | [library/](journeys/library/library_journeys.dart) | Search, scroll, cards/list, Download Manager, artist navigation |
| Artist/album | [detail journeys](journeys/library/detail_journeys.dart) | Library → artist → album → back |
| Playlists | [playlists/](journeys/playlists/playlist_journeys.dart) | Collection layout, existing detail/editor, unsaved new draft |
| Liked | [liked/](journeys/liked/liked_journeys.dart) | Scroll local/server liked tracks |
| Settings | [settings/](journeys/settings/settings_journeys.dart) | Server menu, password validation, statistics toggle, reset cancellation, shuffle scopes, log categories |
| Stats | [stats/](journeys/stats/stats_journeys.dart) | Scroll rankings, open/close history status |
| Player | [player/](journeys/player/player_journeys.dart) | Repeated open/swipe-close, shuffle choices, output picker |

[all_journeys.dart](journeys/all_journeys.dart) registers the journeys.
[ui_profile_test.dart](ui_profile_test.dart) is the separate device entry point.
[support/](support/) contains finders, bounded waits, frame measurements, and the
host report writer. [The driver](../test_driver/ui_profile_driver.dart) saves
reports on the Mac. [Harness tests](../test/ui_automation/) verify bookkeeping,
frame-budget calculations, and inventory references without a phone.

## Run on an iPhone

Keep the device connected, unlocked, trusted, and configured for development.
Existing iOS signing and local-network permissions must already work. Use a
physical device for performance measurements. No Flutter MCP server is required.

```sh
flutter pub get
flutter devices
bash tools/ui_tests/run_profile.sh DEVICE_ID
```

The runner uses `flutter drive --profile --no-dds --keep-app-running` and the integration-test
entry point. It relaunches the app, reuses existing saved app data, and lets the
normal app restore its session. Native permission prompts must be handled before
an unattended run. This is not attachment to an ordinary running profile build.
`--keep-app-running` is essential: Flutter drive's default cleanup uninstalls the
app, which removes its sandbox data and can reset its iOS permission choices.
After testing, launch the normal app entry point with `flutter run --profile -d
DEVICE_ID`; until replaced, reopening the installed test build reruns automation.

Run one feature, several features, or a single journey:

```sh
bash tools/ui_tests/run_profile.sh DEVICE_ID player
bash tools/ui_tests/run_profile.sh DEVICE_ID library,playlists
bash tools/ui_tests/run_profile.sh DEVICE_ID player.tray_transition
```

Optional configuration:

```sh
bash tools/ui_tests/run_profile.sh DEVICE_ID player.tray_transition \
  --dart-define=UI_REPEATS=5 \
  --dart-define=UI_TARGET_FPS=120
```

- `UI_REPEATS`: 1–20, default 3 for scrolling, player transitions/dialogs,
  Stats revisits, collection view switches, artist navigation, Download Manager,
  and Custom Shuffle Artists/Genres view cycles. Ordered tab pairs run once.
- `UI_TARGET_FPS`: optional positive frame rate. Default is the display's reported
  refresh rate (60 fallback); variable-refresh displays may require an explicit
  target. Reports record the chosen budget.
- `UI_SEARCH_QUERY`: default `a`. Use a representative query for your library.
- `UI_CAPTURE_TIMELINE=false`: capture frame timings without a full VM trace.
- `FLUTTER_BIN`: host environment variable selecting a Flutter executable.
- `UI_REPORT_DIR`: host environment variable selecting the report directory.
- `PHONOLITE_URL`: pass the app's existing Dart define when a custom default
  server is needed. No credentials are embedded in the tests.

The full default suite uses real content already on the device. Empty collections,
disabled Stats, absent compact controls, or content too short to scroll are
reported as **skipped with a reason**, never as exercised coverage. Failed journeys
are recorded and navigation is recovered before continuing; any failure makes the
overall test fail. Selected journeys never reached (for example after a startup
failure or overall timeout) are reported as unrun. A skipped journey can have
completed some actions; conservatively none
of its declared interactions count as covered.

## Reports and jank capture

Each run creates `build/ui-profile/<UTC timestamp>/`:

- `REPORT.md`: journey results, frame count, jank percentage, build/raster p95.
- `coverage.json`: every inventory item marked covered or not exercised.
- `run.json`: metadata and raw results, including skips/failures/unrun journeys.
- `<journey>.frames.json`: raw per-frame timings and the slowest frames.
- `<journey>.timeline.json`: full trace events for completed captures, viewable in
  a Chrome trace-event compatible viewer such as Perfetto. This is **not** a
  DevTools export snapshot.
- `build/ui-profile/latest.txt`: path to the latest run.

The host saves a checkpoint after every journey and acknowledges it before the
phone continues. Timeline events stream to the Mac throughout the journey, then
merge with a final snapshot to include event blocks not yet streamed. This avoids
losing early jank when the VM's snapshot ring buffer wraps. Full timelines do not
accumulate in the app's Dart heap. If iOS kills the app or the connection drops,
the report is marked interrupted and previously saved journeys remain available.

Each journey automatically records the actions it drives. Build and raster times
are compared separately to `1 / target FPS`; they are not added. Captures shorter
than 30 frames are marked insufficient, including captures with no frames.
Frames are bounded to 12,000 per journey and truncation is explicit. Frame batches
are flushed around captures; settling/waiting and harness work can contribute to
the measured interval. Do not interpret these as isolated function benchmarks.

Compare like-for-like runs on the same device, refresh target, content, and cache
state. Trace collection and the test harness have overhead. Do not run another
timeline recorder concurrently: tracing changes VM timeline flags/buffers. These
journeys automate selected workloads; they are not a continuously armed recorder
for arbitrary manual usage. CPU hotspot sampling can be done separately through
the profiling MCP after reproducing a specific slow journey. Review raw timeline
arguments before sharing traces outside your machine.

For MCP CPU sampling during an automated workload, use a longer focused run:

```sh
bash tools/ui_tests/run_profile.sh DEVICE_ID settings.custom_shuffle_browse \
  --dart-define=UI_REPEATS=20 \
  --dart-define=UI_CAPTURE_TIMELINE=false
```

Connect the MCP to the VM-service URL printed for that test run and sample CPU
while its view cycles run. The integration driver supplies the gestures. The MCP
screenshot/inspector needs debug mode; its CPU tools work in profile mode.
CPU samples include test bindings and finder traversal, so distinguish that work
from app build/layout work. Preserve the same repeats, dataset, refresh target,
capture settings and sampling window for before/after comparisons. Each journey
records its loaded artist count to help detect a changed dataset. An optimization
still needs behavior checks and measurements; the MCP supplies diagnostics and
the agent makes/reviews the code change.

For a short reproducible case, set the host environment variable
`UI_CAPTURE_CPU=true` on any profile runner. The driver saves per-journey
`.cpu.json` VM samples beside frame reports, with sampling bounded by the same
journey start/result acknowledgements. CPU sampling adds overhead; keep it off
for ordinary frame comparisons.

## Scope and data changes

The initial suite browses screens and dialogs, discards playlist drafts, and
restores layout and statistics-collection preferences after toggling them. Reset
confirmations are cancelled; the password form only submits empty fields for
local validation. It does not submit a playlist,
delete data, change passwords, sign out, start downloads, or deliberately change
playback. Normal app startup/background behavior (session restoration, pending
downloads, logging, and listening synchronization) still runs normally.

Mutating actions remain in the inventory as pending/prerequisite-specific work.
Use confirmed disposable accounts/data for those journeys. Native pickers,
permission dialogs, system audio UI, and OS gestures need native automation
(for example XCUITest/Patrol) or explicit manual coverage. Built-in Flutter taps
are synthesized at the framework level; they do not certify native touch routing.
Text entry uses Flutter's registered test keyboard so client IDs remain valid in
profile mode. It exercises field editing/submission but does not show or measure
the native iOS keyboard, its suggestions, or keyboard-driven viewport resizing.

[The state coverage matrix](STATE_COVERAGE.md) distinguishes physical-device
runs and the connection/data/hardware states still
requiring device runs. A successful journey is not exhaustive state coverage.

All harness logic is outside `lib/`. Regular app builds still enter through
`lib/main.dart`; no test route, menu, runtime flag, or callback is added to it.
The test SDK packages are dev dependencies. Flutter may regenerate native plugin
registration/build files when resolving those dependencies.
The host controls timeline collection over Flutter's existing VM-service
connection. A test-only, acknowledged report channel coordinates capture start
and result export; no diagnostic HTTP client or server-security override is
installed in the app.

## Add or maintain a journey

1. Add/update an action in its feature JSON under `catalog/`.
2. Add a `UiJourney` in the relevant `journeys/<feature>/` file. Use existing
   visible labels, tooltips, widget types and keys; avoid hard-coded coordinates
   except a gesture whose region is computed from its widget's current bounds.
3. Assert the resulting state. Do not call controllers to perform the action
   under test. Controller reads are allowed for prerequisites/assertions; direct
   navigator calls are restricted to recovery between journeys.
4. Link each interaction ID to the journey in its catalog entry. Register the
   journey in `all_journeys.dart` and run the harness tests.
5. Regenerate the inventory/index and run that journey on a physical device.

```sh
python3 tools/ui_tests/catalog.py
flutter analyze integration_test test_driver test/ui_automation
flutter test test/ui_automation
```

Keep runtime results separate from implementation coverage. Adding an inventory
entry or a journey does not mean the action has passed on every device/state.

## Audio playback

The [playbar and quality suite](audio/PLAYER_CONTROLS.md) taps the actual compact
and expanded controls, verifies server-side effects with restoration, and checks
real encoded HQ/MQ/LQ samples. Run it with
`bash tools/ui_tests/run_player_controls.sh DEVICE_ID`.

The separate [audio profile suite](audio/README.md) starts real playback and
measures native output progress, stalls, buffer refills, pause/resume and seek
recovery while retaining UI frame/timeline captures. Run it explicitly with
`bash tools/ui_tests/run_audio_profile.sh DEVICE_ID`; the usual UI journeys
do not start playback.


## Actual disposable account mutations

[The live account entry point](live_account_profile_test.dart) is deliberately
separate. It uses the real server and real authentication/password/reset
protocols, with fresh private client databases and an in-memory credential store.
It reads the existing saved session without writing the normal credential vault.
Do not run it against an account with data or sessions you need.

After the user confirms and signs into a disposable account, provide its exact
nonsecret username as an additional guard:

```sh
flutter drive --profile --no-pub --no-dds --keep-app-running \
  --driver=test_driver/live_account_profile_driver.dart \
  --target=integration_test/live_account_profile_test.dart -d DEVICE_ID \
  --dart-define=LIVE_DISPOSABLE_ACCOUNT_CONFIRMED=true \
  --dart-define=LIVE_EXPECTED_USERNAME=DISPOSABLE_USERNAME
```

Passwords are entered directly into the genuine password form on the iPhone.
When all three fields are complete and confirmation matches, the test submits
them and verifies the current session still works. Passwords are never passed in
Dart defines, stored in reports, or requested in chat. A password change signs
out other sessions for that disposable account. The statistics case confirms
actual account history deletion and checks that the server generation advances.
Use `--dart-define=LIVE_ACCOUNT_CASES=statistics` or `password` to select one.
Reports are saved under `build/live-account-profile/`; manual password entry is
explicit metadata. Restore the normal `lib/main.dart` build afterward.
