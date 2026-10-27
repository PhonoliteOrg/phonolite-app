# Account synchronization contract

This document describes the app/server behavior added around the existing live
likes and playlist synchronization. Source ownership and dependency rules remain
in [the expected architecture](expected-architecture.md). Server-side protocol
details are in [account state synchronization](../../phonolite-server/docs/account-state-sync.md).

All API paths below are relative to the authenticated `/api` base. Capabilities
come from the existing capability response. A capability value of `"1"` enables
the corresponding feature; an older server continues its existing collection,
playback and local-storage behavior without receiving unsupported mutations.

## What is shared

| Area | Shared account state | Device behavior |
| --- | --- | --- |
| Listening statistics | Accepted listening contributions, totals and reset generations | Both simultaneously playing devices count. Collection consent and local history remain device-specific. |
| Saved custom shuffles | Named artist/genre rules and their revisions | Applying a rule changes only this device. Active server filters are stored per account; local filters remain on the device. |
| Catalogue changes | Committed library generation and artist/album metadata changes | Loaded server views refresh while current audio and downloaded files remain available. |
| Account and access | Current username/role and token validity | Revoked app sessions stop streaming and require sign-in. Users can keep the current app session or sign out every app session; admin console sessions remain signed in. |
| Starting track | The latest server-accepted successful server-track start | An empty new session prepares that track paused at position zero and then plays independently. |

Existing server likes, playlist names/deletions and playlist-track membership
continue to update across clients, including open add-to-playlist dialogs. Local
likes and local playlists keep their own device storage.

## Revision and event recovery

The `account_events_v2` capability enables:

| Request | Response or event |
| --- | --- |
| `GET /account/state` | `{user_id, username, role, revisions: {collections, presets, statistics}}` |
| `GET /account/events` | Authenticated SSE `account` events with `{kind, revisions}` |

`ready` means the subscription is installed. Clients subscribe before fetching
snapshots, then reconcile revisions observed while those reads were in flight.
`revision` invalidates committed domains; `account_changed` refreshes account
metadata even when data revisions are unchanged. The three clocks belong to
their stores and do not imply a shared cross-database transaction. The original
collection snapshot/event endpoints remain supported.

Events are invalidation hints. A reconnect, foreground recovery, missed event,
or database restore is repaired by authoritative snapshots. A new stream can
accept lower clocks after a restore. The server also checks durable account
revisions every 15 seconds, so a lost in-memory publication is eventually repaired.
Transient reads retry with bounded coalescing/backoff; account/session generations
reject late reads and mutation replies belonging to an earlier account.

An unauthorized event connection requires sign-in. Cancellation releases the
stream body, including a response that arrives after cancellation. Feature
capabilities and authenticated account state are cleared when the session ends.

## Listening statistics

Account statistics revisions are invalidated only after committed server changes.
Clients respond by pulling counter state and changed month snapshots. A pull does
not upload contributions, update consent or activate the legacy writer, so
receiving an event cannot create another statistics write/event loop.

The existing protocol remains authoritative:

| Request | Purpose |
| --- | --- |
| `GET /stats/state?device_id=...` | Account identity, generation, consent/checkpoint and month revisions |
| `POST /stats/batch` | Idempotent sequenced device counter contribution |
| `GET /stats/snapshot?...` | Paged committed month snapshot |
| `POST /stats/preferences` | Explicit device collection preference change |
| `POST /stats/reset` | Account reset with the existing history-generation fence |

Active playback schedules uploads approximately every 20 seconds while local
collection is enabled. The existing listening synchronizer owns pending batches,
acknowledgements and retries. Two devices playing for the same minute contribute
two minutes of listening. Reset generations, per-device batch sequences and
consent barriers continue to reject stale or repeated contributions.

Legacy pending events drain using their original IDs before that device activates
the counter protocol. No notification migration resets an account or silently
imports unrelated local history.

## Saved custom shuffle presets

The `shuffle_presets` capability enables named account rules:

| Request | Contract |
| --- | --- |
| `GET /account/shuffle-presets` | `{revision, items}` |
| `POST /account/shuffle-presets` | Create from `{name, artist_ids, genres}` |
| `POST /account/shuffle-presets/:id` | Update those fields with `expected_revision` |
| `DELETE /account/shuffle-presets/:id?expected_revision=N` | Delete the expected version |

Each item is `{id, name, artist_ids, genres, revision}`. The server generates IDs,
trims name whitespace, accepts names of 1–80 characters, deduplicates filters and
normalizes genre case. Missing catalogue choices can remain in a saved rule.
Updates without a precondition return 428; stale edits/deletions return 409.

Custom shuffle settings shows the existing list style and add/edit/select/delete
actions. Its modal reuses the artist/genre controls and adds a preset name. An
open editor keeps its draft when another device changes or deletes the preset;
the user can reload the current version or save a copy. Changing accounts disables
that account's open draft. Applying a preset is an explicit local playback action;
remote preset edits do not rewrite an already-playing device's queue.

The app stores active server filters under a SHA-256-derived filename for the
authenticated server identity and user ID. Account changes clear those active
fields before loading the new scope. Local artist/genre filters remain separate.
The old `shuffle_settings.json` server fields are retained for **Import existing
filters**, which explicitly creates an account preset. New local saves update
only local fields in that legacy file.

Repeat persists in `playback_prefs.json` for this device. If no local repeat value
exists, the first accepted legacy server repeat setting is migrated once. Later
account changes do not replace it, and a user toggle wins over an in-flight load.

## Catalogue changes

The `catalogue_events` capability extends `GET /library/metadata-events` with
`kind: "catalogue"`; its `id` is the opaque `browse_revision`. Existing metadata
event shapes remain supported. Initial/periodic markers and markers after a
committed scan, reindex, root replacement or restore invalidate retained browse
windows/cursors and relevant loaded server views.

Clients compare generations instead of retaining stale indexes. Recovering an
interrupted refresh can retry the same generation. This refresh does not restart
audio or delete downloaded media. Artist/album metadata refreshes retain their
existing targeted update behavior.

## Account access and sign-out

The `session_management` capability enables:

| Request | Result |
| --- | --- |
| `POST /account/sessions/revoke-others` | `{revoked}`; app sessions only, preserving the exact initiating token and admin console sessions |
| `POST /account/sessions/revoke-all` | `{revoked}`; app sessions only, including the initiating token and preserving admin console sessions |

Settings offers both actions with confirmation explaining that affected streams
stop and those app devices must sign in again. Admin console sessions remain
signed in for both actions, including the server-console per-user action.
Requests are scoped before confirmation
and checked again before execution, so switching accounts cannot redirect an open
confirmation. A missing acknowledgement is reported as unconfirmed instead of
claiming that no server change occurred. Revoke-all may invalidate its event
stream before the HTTP acknowledgement arrives.

Server-console administrators also have a per-user sign-out-all action under the
existing role hierarchy and Superadmin protection. Account deletion, revoked or
expired access, and password/role changes that revoke tokens invalidate affected
long-lived streams. The server wakes those streams immediately and retains
periodic revalidation, including QUIC's existing checks. Sign-out invalidates
server access without deleting downloaded local media.

## Independent starting track

Servers advertising `playback_resume: "1"` use the durable playback checkpoint
protocol below. The `last_track` behavior in this section remains the fallback
for older servers.

The `last_track` capability enables:

| Request | Contract |
| --- | --- |
| `GET /account/last-track` | `{track_id: string|null, revision}` |
| `POST /account/last-track` | `{track_id, session_id, sequence, request_id}` after a confirmed successful server-track start |

The server orders accepted concurrent starts by commit order. A runtime session
nonce, increasing sequence and stable request ID prevent retries or older starts
from overwriting a later start from the same session. Offline history and local
tracks do not update this live reference. Missing or removed tracks return null.

A transient report failure permits one retry with the same request identity
while the exact session and track selection remain current. Stop, another track,
an account change or shutdown retires that retry; no offline start reports are queued.

A new authenticated app uses the reference only while its own track/queue is
empty and no newer playback action has superseded the read. It prepares the track
paused at position zero. It does not import a seek position, queue, repeat,
shuffle, volume or play/pause state. Existing sessions continue independently.
An unavailable reference or failed lookup leaves ordinary playback usable.

## Durable playback checkpoints

`GET /account/playback` returns `{revision, generation, checkpoint, reason?}`.
A checkpoint contains `track_id`, logical `source`, `shuffle_mode`, applied
`shuffle_context`, optional `deck_id`, and an absolute `cursor`. Source contexts
identify standalone/library/liked/playlist/album/artist/custom selections; private
playlist IDs are always resolved under the authenticated account. Custom contexts
carry the applied artist/genre rules, independently of subsequent preset edits.

`POST /account/playback` submits the complete checkpoint with `expected_revision`,
`session_id`, monotonic `sequence`, stable `request_id`, and `intent` (`start` or
`update`). An update also supplies its server-issued `generation`. Importing a
live shuffle deck supplies the owning `client_id`; later reads use the durable
account-owned deck through `GET /account/playback/decks/:id?offset=N&limit=10`.
Each player owns its cursor. No remote transport commands are implied.

New successful online starts publish the account bookmark. Source/shuffle updates
cannot overwrite another playback generation, and conflicts refresh cached
account state without interrupting audio or replaying stale writes. A stable
request ID identifies retries of the same payload. Offline history is not promoted
into a new account bookmark on reconnect. Legacy clients' track-only reports
replace incompatible context with a standalone track.

The app separately stores a device-local permutation, current cursor, modes and
seek position, and an account-scoped resume cache. Device snapshots use application
support storage with atomic, serialized writes. Local-data reset retires pending
saves; unsupported future schemas are retained rather than overwritten. Local
queue IDs and file paths never enter account requests. Server playlist authority
is retained when its audio happens to play from a downloaded file.
An account switch detaches a continuing downloaded server queue to a standalone
device bookmark, removing the previous account's private source without
restarting its audio. Paused custom-filter edits save the applied rules as soon
as their queue refresh completes.

Restoration waits for the local library and preferences, prepares paused state,
and does not start audio or report listening. An explicit playback action always
wins over an in-flight restore. The last local session takes precedence over an
account suggestion; server playback uses the latest authenticated account
checkpoint. Network failures retain caches for later resolution.
An offline cold start can use downloaded audio metadata only when secure saved
credentials identify the verified account UUID and trusted server. Its original
source and durable deck resolve on explicit navigation after reconnection, even
when another device has since advanced the account bookmark.

Saved sources and track membership are validated on restoration. Removed entries
are skipped without changing surviving shuffle order; deleted sources detach to a
standalone track when that track remains playable. Empty sources never broaden to
all tracks. Missing local files are unavailable even if download metadata remains.
Temporary server/catalogue failures defer restoration instead of erasing history.
Account notifications refresh resume information without changing an active
player. Stop retains a bookmark; reset clears local playback data.

## Verification

Use static analysis and focused foreground headless tests for protocol framing,
account isolation, revision rollback/reconnects, draft conflicts, session changes,
statistics idempotency, seed ordering and preference migration. Application/device
launches and server startup remain user-controlled; live multi-device checks must
be performed by the user after starting their own app/server instances.
