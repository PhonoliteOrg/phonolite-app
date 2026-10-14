# phonolite_app

Phonolite Flutter client.

## Desktop controls

On Windows, macOS, and Linux, press Space to pause or resume playback. Holding
Space toggles only once. Text fields, focused controls, and dialogs retain their
normal keyboard behavior; modified combinations such as Ctrl+Space do not
toggle playback.

On Windows, macOS, and Linux, Mouse 4 (Back) performs the active tab's
"Back to..." action. Mouse 5 (Forward) reopens pages backed out of with either
the mouse or the on-screen Back button. Each tab keeps its own history; opening
a different page clears that tab's forward history. Back at a tab's starting
page does nothing.

## Encrypted server connections

Enter the server IP/host and port (default `3000`), then your username and password.
Connect opens a TLS 1.3 connection and checks `/api/v1/health` before showing
the sign-in form. A spinner stays in the button while checking; unreachable
addresses, invalid health responses, expired certificates, and changed saved
certificate pins leave the address form open with an error. This public check
sends no credentials and does not establish new server trust.
Sign-in runs OPAQUE in the native
Rust package, binds the proof to the TLS connection, verifies the server, and
remembers its public-key pins automatically. Sign-in sends OPAQUE proofs instead
of the password. API calls, artwork, SSE, downloads and QUIC audio
require the authenticated identity. HTTP fallback, unverified streaming, and
redirects carrying credentials to another server are blocked.

Server pins are retained in OS secure storage even without **Remember me**.
Remember me additionally stores the bearer session there. Passwords are not saved.
A changed server identity fails closed; restore the original server key and database
backup. A new certificate with the same key keeps the same pin.

Settings groups listening statistics and their reset actions under **User**, below
**General**. **Reset user password** appears only while connected and opens its
own page with the same heading, fields, and controls as server sign-in. It requires
the current password and a nonempty password (at most 1024 UTF-8 bytes), with no
strength or password-reuse policy. This operation sends the current and new
passwords only inside the existing authenticated, pinned HTTPS connection to
the trusted server, with no plaintext fallback, redirects, or automatic retries.
Passwords are not saved or logged. A successful change keeps this device's
existing session and remembered sign-in, while revoking the account's other
sessions. Playback and downloads continue without signing in again. If a response
is lost, the session is kept; check which password took effect before trying again.

This is a breaking authentication implementation for new installations. Create
new accounts on a fresh server database; existing accounts and saved sessions are
not migrated. Old `auth.json` files are ignored and left untouched. See the server
README's Authentication section for `--setup-admin` and `--renew-certificate`.
The browser admin interface is local
to the server at `https://127.0.0.1:3002`. TLS must terminate directly in Phonolite;
ordinary TLS-terminating reverse proxies are incompatible with the channel binding.

The fixed OPAQUE profile uses Ristretto255/3DH/SHA-512 and Argon2id (64 MiB, three
passes). Password work runs off the UI isolate at sign-in; the server also uses
the same profile when verifying and enrolling a password change.
TLS 1.3 and QUIC perform bulk authenticated encryption using native crypto libraries,
with AES hardware acceleration where available and ChaCha20-Poly1305 support.
Code verification does not establish streaming performance on every device.

Native builds include `flutter_secure_storage`: Windows uses OS protected storage,
Apple platforms use Keychain, Android uses its secure storage backend, and Linux
requires a running desktop Secret Service when the user runs the app. Linux build
dependencies include `libsecret-1-dev` and `libjsoncpp-dev`; runtime packages include
libsecret and jsoncpp. macOS runner entitlements include Keychain Sharing. Web
sign-in is not supported by this native authentication implementation.

Genres use consistent title case across library cards/rows, detail headers,
shuffle options, and statistics, including cached and offline metadata.
`alternative rock` displays as `Alternative Rock`; acronyms such as `R&B`, `EDM`,
and `IDM` retain their customary casing. Saved metadata and lowercase shuffle
selection keys keep their existing values.

## Local application logs

Logs are saved automatically in debug and release deployments. Each file keeps
exactly the newest 3,000 entries once full, removing only the oldest entries as
new ones arrive. Files persist across app restarts. Multiline messages and stack
traces are escaped onto one physical line per event.

| Platform | Default log directory |
| --- | --- |
| Windows | `%LOCALAPPDATA%\Phonolite\logs` |
| macOS | App's Application Support directory, under `logs` |
| Linux | App's XDG data directory, under `logs` |
| Android | App's private support/files directory, under `logs` |
| iOS | App's sandboxed Application Support directory, under `logs` |

On Windows, Application Support is used if `LOCALAPPDATA` is unavailable. The
exact resolved folder is shown in **Settings → Local Storage → Logs storage**
and **Settings → Logs**. Change selects a log folder and preserves the current
history; Reset restores the platform's default folder. The selection persists
across restarts. Only the app's category log files move; other files are kept.
Desktop platforms also provide Open folder; iOS manages the log location automatically.
Log storage is configured separately from downloaded music and metadata, and
Reset local data clears log history and all category log files while keeping
storage folder choices. A new log entry records the completed reset.

Files use the server's category names: `all.log`, `info.log`, `activities.log`,
`warnings.log`, `errors.log`, `issues.log`, and `debug.log`. Status events go to
activities; warnings and errors also go to the combined issues file. Each file
has its own independent limit. Settings → Logs restores the latest overall
history, filters it by category, and supports Copy All. Clear removes the
overall history and empties all seven files, including when a filter is active.
The viewer builds only visible rows, batches live updates at most ten times per
second, and formats the complete history only when Copy All is pressed. Opening
the page uses the bounded in-memory history without rereading the files.

Missing artwork (HTTP 404/410) uses the usual placeholder and records an Info
event. Other artwork failures record a Warning without a stack trace. Repeated
failures for the same image and status are logged at most once per five minutes;
unrelated Flutter errors keep their normal error handling.

Writes run in a serialized asynchronous queue, with bursts batched together and
full files replaced after trimming. Storage failures appear in the Logs page and
in-memory history while the app continues operating. Browsers do not write local
filesystem logs. Constructing a logger does no I/O; tests enable persistence
explicitly with an injected temporary directory.

## Resuming downloads

Artist and album download requests are saved locally with their complete track
or album plan before the first staging window begins. Only 20 tracks are staged
at a time; restarting the app restores the full request and continues staging
the remainder once the server session is restored. Unstaged tracks that need
server metadata wait for sign-in. A failed plan save prevents the download from
starting, so an incomplete request cannot silently replace the full selection.
Artist album plans are saved before contacting the server and retained alongside
v2 manifests. Interrupted album lookups and failed tracks retry when the server
session reconnects; they do not discard the artist request. Progress updates
preserve tracks that finish while further albums are being discovered.
Deleting a downloaded artist also removes its failed downloads and saved artist
or album requests, so those requests cannot restart or leave a retry indicator.
Reset local data stops active downloads and clears every local download status,
plan, partial file, and cached failure. Responses from requests started before
the reset are discarded, including metadata and artwork, so they cannot restore
old work or overwrite downloads requested afterward.

## Artist collaborations

The Artists list, search and custom shuffle selection include main album and
song artists and explicitly featured guests. Supporting credits such as writers,
producers and session musicians remain in detailed credits; a supporting role
alone does not create a visible artist profile.

Artist profiles separate **Albums** for solo headline releases from **Collab
albums** for jointly billed releases, **Appears on** for billed song appearances,
and **Other credits** for supporting contributions to releases outside that
artist's headline albums. Solo and joint headline releases do not repeat under
Other credits; their detailed album and song credits remain available. This also
applies offline and when connected to older servers. A joint release
keeps one shared album ID and appears once under each main artist. All release
sections share the album card/list layout; selecting a release opens the full album.
Artist downloads and album removal selection cover solo and joint headline
albums. Guest and supporting credits do not select unrelated album tracks.

Main and featured artists have independent metadata profiles. Downloaded profiles
use the same billing rules and sections for music on the device. Existing stored
contributor metadata remains readable. Credits retain artist IDs, credited names, roles and joining words through
playback and offline metadata; legacy single-artist metadata remains readable.
Configured metadata providers can enrich individual profiles when a matching
identity is available.

The server resolves identities from structured artist tags, clear list or
featured-artist separators, and independent identity evidence for ambiguous
punctuation. Legitimate compound band names stay intact. Existing catalog
organization is repaired during the next normal server startup after upgrading.

## Controller lifecycle

Constructing `AppController` does not start audio, storage loading, subscriptions,
or timers. Call and await `initialize()` before restoring a session; repeated calls
share the same startup future. `close()` provides awaitable, idempotent cleanup,
including partial startup. Flutter owners can use `dispose()` to begin cleanup.
Audio factories, offline storage/downloads, settings stores, connectivity, and
platform adapters can be injected for tests without starting native workers.

## Pause, seeking, and recovery

Pausing preserves the active audio session. Resume reuses its buffered audio even
after a long pause; it opens a replacement only when the session is unavailable.
Remote playback receives compressed Opus packets into a bounded cache separately
from the short PCM output queue. A full PCM queue cannot block incoming seek
announcements. Cached targets seek locally with decoder preroll; missing targets
request a server range. Compatible output flushes queued samples while keeping
the selected device open, using 40ms PCM submissions.

The client cache has a 16MiB budget that counts compressed packets and estimated
allocation overhead, with eviction and a 64-range limit. This cache survives
pause and seek but is released when the session is replaced. Server audio is
indexed in five-second ranges, keyed by
source version and rendition. The native delivery queue is bounded to 512KiB.
These transient caches are separate from downloaded offline tracks.

Scrubbing changes the preview position, and release commits one seek. The worker
acknowledges readiness or failure with a five-second deadline; replaced requests
cannot restart a newer session. Paused replacements begin paused without a
delayed pause command. Stream announcements identify the source, request, and
range end so reaching a range boundary does not finish the track.

Transport failures retain the user's play intent. Repeated interruptions wait
for a successful server health check and the retry cooldown before trying again.
Pressing Pause or Stop cancels that recovery. Playback clocks and audio adapters
are injectable so these transitions can be verified without an app or server.
If the audio worker exits unexpectedly, the next Play starts a fresh worker
with the current volume and output device settings.

QUIC ranges keep the selected starting quality stable, including the legacy
`AUTO` mode. Adaptive PCM buffering still responds to network conditions; the
server does not switch bitrate inside a cached range. Rebuild both the client
and server for the updated range protocol and native audio-flush interfaces.

## Listening statistics

Listening statistics are enabled by default. **Settings → User → Listening
statistics** turns collection off for this installation. Off immediately stops
new listening records and prevents queued records from being uploaded; it does
not erase history already saved locally or on the server. Other installations
keep their own collection setting. Re-enabling starts recording new listening
without uploading the queue excluded by opt-out.

**Reset listening statistics** in **Settings → User** asks for confirmation and
is hidden while listening statistics are turned off. It clears all listening
statistics saved on this device. While connected and signed in, it also clears
the connected account's server statistics; offline, the server is left alone.
Other devices keep their saved statistics until the user resets each device.
After a server reset, those retained copies stay local and are not uploaded again.
The collection setting is preserved, and enabled collection starts fresh listening.
Reconnecting after an offline reset can download statistics still held on the server.

The Stats page works offline and uses the same panels, controls, and responsive
layout as the rest of the app. It shows listening duration, qualified plays,
distinct tracks and artists, rankings, and synchronization status. Collection
counts consumed audio rather than seek positions. A play qualifies once after
30 seconds or half the track's duration, whichever is shorter; pause/resume and
seeks stay within the same play, while repeat playback starts another.

Top Artist tiles open the artist in Library. Most Played Track tiles open the
track's album with the Library → Artist → Album back stack, without starting
playback. Downloaded music provides destinations offline; unavailable items
leave the Stats page open and show a message.

History is stored in a dedicated application-support `stats.sqlite`, separate
from downloaded music and the offline-library database. Checkpoints are written
by a serialized storage worker after 15 seconds of consumed audio and at playback
boundaries. An abrupt process termination can lose the uncheckpointed tail.
UTC occurrence dates determine monthly and yearly reports; late uploads update
the original period. Duration totals sum actual playback across devices.

When signed in to an updated server with server statistics enabled, the app
uploads aggregated monthly deltas and downloads changed monthly snapshots
opportunistically on login, resume, reconnect, refresh, and every five minutes.
Each account/device keeps one immutable outstanding batch; retries reuse its
sequence and payload. New listening keeps accumulating separately. Cache updates
and retiring the covered batch commit together so reports never double count it.
Poor connectivity never blocks playback or saving locally.
Anonymous history stays separate until **Include local history** is confirmed.

New checkpoints update existing counter rows rather than retaining event records.
Shared metadata snapshots, monthly counters, a bounded recent playback state, and
one device checkpoint replace permanent event and checkpoint histories. Existing
pending event IDs are reconciled during upgrade before legacy rows are compacted.

Existing event-based history migrates into counters during upgrade. Older
aggregate-only server totals remain available through the existing stats endpoint;
they lack the device ownership needed for duplicate-safe offline import.
See the server's `LISTENING_STATS.md` for the synchronization protocol.

## Library search

Local library search and the server search API use the same normalization and
Damerau–Levenshtein matching rules. Missing apostrophes, punctuation, extra spaces,
and joined or split words are handled through a compact comparison form. Fuzzy
word/span matching allows one letter edit for 4–7 characters and two for 8 or more;
1–3 character terms stay literal. Edits include adjacent letter swaps. Exact and
spacing-equivalent matches rank above fuzzy matches, and the result limit applies
after ranking. Original titles and artwork are preserved. Fuzzy comparisons are
bounded to 64 characters per word/span; longer literal queries still work.

The app and server keep matching score vectors in `library_search_vectors.json`
under their search test fixtures. Update both copies when changing the rules.

## Tests without servers

`flutter test --no-pub` excludes the `requires-server` tag by default, as configured
in `dart_test.yaml`. Persistence and controller tests use temporary directories or
in-memory dependencies. HTTP-server fixtures are kept separately under
`test/server_integration` and remain disabled during ordinary verification.

## Setup

1. Clone and init submodules:

```bash
git submodule update --init --recursive
```

2. Install packages:

```bash
cd phonolite_app
flutter pub get
```

## Native FFI Libraries
1. `phonolite_quic` builds from Rust during platform builds.
2. Android builds require `cargo-ndk` and the Android NDK installed.
3. iOS/macOS builds require Xcode command line tools.
4. Windows/Linux builds require the Rust toolchain in `PATH`.

## Build / Run

Android (macOS/Windows/Linux):
```bash
flutter run -d android
flutter build apk
```

iOS (macOS only, requires Xcode + CocoaPods):
```bash
flutter run -d ios
flutter build ios --release
```

macOS:
```bash
flutter run -d macos
flutter build macos
```

Windows:
```bash
flutter run -d windows
flutter build windows
```

Linux:
```bash
flutter run -d linux
flutter build linux
```
