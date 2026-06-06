# Phonolite App Requirements

## Status
- Document type: Implementation-derived requirements baseline
- Scope: Current `phonolite-app` Flutter client, native platform layers, and bundled FFI packages
- Source coverage: `lib/**/*.dart`, `android/**`, `ios/**`, `macos/**`, `windows/**`, `packages/phonolite_opus/**`, `packages/phonolite_quic/**`, and vendored platform plugin patches under `packages/**`
- Purpose: Capture the behavior currently implemented in code so product, engineering, and testing can track changes against a single versioned baseline
- Interpretation rule: Unless explicitly marked as a constraint, each item below describes behavior that must be preserved for compatibility with the current client

## Notes
- This file is extracted from the current implementation. It is not a future-state wish list.
- Some entries describe current limitations, safety tradeoffs, or platform-specific constraints because they materially affect behavior.
- Requirements are grouped by concern and use stable IDs so later work can trace features, tests, and design changes back to this document.

## Application Shell and Visual System
- UI-001: The app shall start from a single Flutter entrypoint that creates a `PhonoliteApp`, disables runtime Google Fonts fetching, and injects a single `AppController` into the widget tree.
- UI-002: The app shall use a dark "Obsidian" visual language with near-black backgrounds, gold accent highlights, Rajdhani display typography, and Poppins body typography.
- UI-003: The app shall use chamfered, glass-like, or clipped geometric surfaces across cards, buttons, dialogs, and navigation controls.
- UI-004: The app shall support responsive scale-down through `ObsidianScale`, clamping UI scale between `0.7` and `1.0` based on a `900px` baseline width.
- UI-005: The app shall preserve hover-specific affordances on desktop-capable targets and avoid hover dependence on touch-first targets.
- UI-006: The app shall disable backdrop blur on web and Windows, even when glass-styled components remain visible.
- UI-007: The app shall disable image precaching on web and Windows.
- UI-008: Album artwork placeholders shall render a gold gradient square with the album title initial when no cover image is available or image loading fails.
- UI-009: Artist artwork placeholders shall render a gold gradient circle with the artist initial when no artist logo is available or image loading fails.
- UI-010: Artist logo and album backdrop colors shall be derived from deterministic fallback color logic so missing or failed remote images still produce visually stable headers.
- UI-011: Text summaries for artists and albums shall support collapsed and expanded presentation, with a "Read more" or "Collapse" control once content crosses the configured threshold.
- UI-012: Long text in constrained presentation areas shall be handled either by ellipsis or marquee-style horizontal scrolling, depending on widget context.
- UI-013: Empty-state views shall present explicit title and message text rather than silent blank screens.
- UI-014: Shared command buttons shall use explicit labels such as "Back to library", "Back to artist", or "Back to settings" instead of relying only on gesture navigation.
- UI-015: The app shall preserve a secondary full-screen search page implementation in code, even though the main navigation currently uses inline library search.

## Startup, Session, and Authentication
- AUTH-001: The app shall derive its initial server base URL from the compile-time environment variable `PHONOLITE_URL`, defaulting to `http://127.0.0.1:3000/api/v1`.
- AUTH-002: On startup, the app shall attempt saved-session restoration before showing the main authenticated experience.
- AUTH-003: Session restoration shall show a branded splash screen while attempting reconnection.
- AUTH-004: Session restoration shall time out after `10s` and fall back to a fresh login flow rather than hanging indefinitely.
- AUTH-005: The stored-session validation request used during restore shall time out after `4s` and shall not use normal retry behavior.
- AUTH-006: If saved credentials are missing, invalid, or cannot pass playback-settings validation, the app shall reset into a fresh login flow.
- AUTH-007: Fresh-login reset shall clear active playback state, clear queues, clear now playing state, and restore the controller to an unauthorized state.
- AUTH-008: The login flow shall be two-stage: connect to a server first, then show username and password entry after the server probe succeeds.
- AUTH-009: The login screen shall accept either host-and-port input or a pasted URL and normalize it into the app's `/api/v1` base URL.
- AUTH-010: The login screen shall provide an explicit HTTP/HTTPS scheme toggle.
- AUTH-011: The login screen shall validate ports into the range `1..65535`.
- AUTH-012: The login screen shall offer a "remember me" option controlling whether credentials are persisted.
- AUTH-013: When saved credentials exist, the login flow shall prefill and normalize the remembered base URL back into host, port, and scheme fields.
- AUTH-014: Successful password login shall persist base URL, token, and username only when the user chose to remember credentials.
- AUTH-015: Token-based login shall also be supported internally for restored sessions and trusted handoff flows.
- AUTH-016: Logout shall optionally clear persisted credentials and shall always disconnect the current client session.
- AUTH-017: The app shall surface authorization failure and server-connection errors through the login UI rather than failing silently.

## Navigation and App Structure
- NAV-001: The authenticated shell shall expose five top-level destinations: Library, Playlists, Liked, Stats, and Settings.
- NAV-002: Each top-level destination shall keep an independent nested `Navigator` stack so that switching tabs does not destroy in-tab drilldown history.
- NAV-003: Back navigation shall first pop the active tab's nested navigator before leaving the current shell route.
- NAV-004: Wide layouts at or above `980px` shall use a left-side icon rail and a full now-playing bar.
- NAV-005: Narrower layouts shall use a bottom navigation bar and a compact mini now-playing bar above it.
- NAV-006: The full now-playing bar shall adapt between wide, compact, and tight layouts at approximately `860px` and `520px`.
- NAV-007: On smaller layouts, tapping the mini now-playing bar shall open an expanded bottom sheet for transport and playback controls.
- NAV-008: The home shell shall observe app lifecycle changes and forward them into the controller.
- NAV-009: The shell shall support opening the currently playing album from the now-playing surface by switching to the Library tab and drilling into the relevant artist and album detail views.

## Library Browsing and Search
- LIB-001: The library shall load artists lazily and page them from the server in increments of `60`.
- LIB-002: Artist pagination shall support infinite scrolling and explicit "load more" behavior until the server indicates no more artists are available.
- LIB-003: The library shall support both card and row-list presentation for collections.
- LIB-004: The collection list/card preference shall be persisted and reused across library and artist detail contexts.
- LIB-005: Artist cards shall show artist artwork when available and shall otherwise fall back to avatar initials.
- LIB-006: Artist rows shall show album counts and up to two genres in the subtitle line.
- LIB-007: Artist detail views shall load all albums for the selected artist and shall attempt to refresh artist metadata independently of the parent list payload.
- LIB-008: Artist detail headers shall support artist logo, optional artist banner, genre line, and expandable summary text.
- LIB-009: Album cards and rows shall show cover art, release year when known, track count, and a limited genre summary.
- LIB-010: Album detail views shall show a hero section with cover art, title, artist, year, genres, and expandable summary text when summary content exists.
- LIB-011: Album detail views shall load tracks once per album selection and shall show an explicit empty state when no tracks exist.
- LIB-012: Library search shall be in-page, debounced, and not fire remote requests for effectively empty queries.
- LIB-013: The primary library search flow shall require a non-trivial query before remote search results are shown.
- LIB-014: The library search flow shall debounce typing by approximately `450ms` before searching.
- LIB-015: Search results shall support artist, album, and track result kinds.
- LIB-016: Selecting an artist search result shall load the artist and navigate to artist detail.
- LIB-017: Selecting an album search result shall load the album, load the related artist, and navigate through artist detail into album detail.
- LIB-018: Selecting a track search result shall load the track, resolve its album and artist, hydrate the album track list, queue the album starting from the selected track, and navigate to the owning album.
- LIB-019: The alternate full-screen search page shall expose explicit filter chips for artist, album, and track filtering.
- LIB-020: Search result rows shall use stable iconography by kind: person for artist, album for album, and music note for track.
- LIB-021: When connected and authenticated, the Library page shall show locally downloaded music and connected-server catalog results in separate source-labeled sections.
- LIB-022: When offline or unauthenticated, the Library page shall show the locally downloaded track catalog from the offline database.
- LIB-023: Album detail views shall expose a compact album download action that queues missing or failed tracks through the batch download manager.
- LIB-024: Artist detail views shall expose a confirmed artist download action that fetches album tracks, deduplicates track IDs, and queues one batch through the download manager.
- LIB-025: The Library header shall expose a Download Manager action in both connected and offline library modes.
- LIB-026: The Download Manager shall render as a drawer-style panel on wide layouts and a sheet-style panel on narrow layouts.
- LIB-027: Downloaded music in the Library shall mirror the server catalog drilldown: downloaded artist cards or rows open downloaded album cards or rows, which open downloaded track rows.
- LIB-028: Downloaded artist, album, track-list, and now-playing views shall prefer locally cached artwork paths when offline metadata contains them.

## Track Lists and Interaction Surfaces
- TRACK-001: Track rows shall show index or animated now-playing bars, title, artist/album summary, and formatted duration.
- TRACK-002: Track rows shall optionally show album art when used in contexts such as liked songs.
- TRACK-003: Track rows shall expose an add-to-playlist control when the surrounding screen allows playlist insertion.
- TRACK-004: Track rows shall expose a like/unlike control in all music-list contexts.
- TRACK-005: Track rows shall expose a delete control only in contexts where track removal is valid, such as playlist detail.
- TRACK-006: Track rows shall support tap-to-play behavior where the owning screen expects playback initiation.
- TRACK-007: Track rows shall support long-press behavior when a screen uses it for alternate playback or queue actions.
- TRACK-008: Track list containers shall preserve divider-separated lists rather than undifferentiated scroll views.

## Playlists, Likes, Stats, Settings, and Logs
- FEAT-001: The Playlists page shall load local playlists on first use and shall also load connected server playlists when authenticated.
- FEAT-002: Playlist cards shall support tap-to-open and long-press-to-queue-playback.
- FEAT-003: The Playlists page shall expose a "Create New" action from the header.
- FEAT-004: Playlist creation and rename flows shall use a modal editor with a maximum name length of `24` characters.
- FEAT-005: Playlist editor modals shall prevent empty or whitespace-only playlist names from being saved.
- FEAT-006: Playlist detail views shall show rename and delete actions in a top banner.
- FEAT-007: Playlist deletion shall require explicit confirmation before removal.
- FEAT-008: Playlist track removal shall require explicit confirmation before removal.
- FEAT-009: Playlist detail views shall show an empty state when the playlist contains no tracks.
- FEAT-010: The add-to-playlist modal shall support playlist search, shall indicate existing membership, and shall support removal from a playlist when removal is available.
- FEAT-011: Liked Songs shall be presented as a dedicated top-level destination rather than as a filter inside Library.
- FEAT-012: The Liked page shall show separate sections for local liked downloads and connected server liked songs, with server liked songs visible only when authenticated.
- FEAT-013: Tapping a local liked download shall play from local downloaded playback, and tapping a connected server liked song shall play from the server liked-tracks queue.
- FEAT-014: The Stats page shall load listening statistics on demand and show an empty state when no stats are available.
- FEAT-015: Stats shall support year changes and month changes, including an "all months" mode.
- FEAT-016: Stats shall present total playtime, top artists, top tracks, top genres, and most-played track rankings.
- FEAT-017: The Settings page shall show current server information, playback-related actions, diagnostics access, and session controls.
- FEAT-018: The Settings page shall show a summarized custom-shuffle selection count and route into custom shuffle management.
- FEAT-019: The Settings page shall show current log count and route into the logs viewer.
- FEAT-020: The Settings page shall expose a logout action labeled as disconnection from the current server.
- FEAT-021: The Logs page shall show buffered diagnostic events, support copying all visible entries, and support clearing the in-memory log buffer.
- FEAT-022: Log entries shall preserve timestamp and log-level labeling.
- FEAT-023: Local playlists and connected server playlists shall be separate copies and shall be allowed to differ.
- FEAT-024: Local liked downloads and connected server liked songs shall be separate copies and shall be allowed to differ.
- FEAT-025: Server library, server playlist, server liked-song, streamed now-playing, and connected playback actions shall update server likes only.
- FEAT-026: Offline library, local playlist, local liked-song, and downloaded playback actions shall update local likes only.
- FEAT-027: Add-to-playlist actions shall be scoped to the current source: local contexts shall show only local playlists, and server contexts shall show only connected server playlists.
- FEAT-028: Local playlist actions shall accept only tracks with a completed local download, while server playlist actions shall continue to use server playlist APIs and server track IDs.
- FEAT-029: The Settings page shall expose separate editable storage locations for the offline metadata database and downloaded audio files.

## Custom Shuffle
- SHUF-001: Custom shuffle shall support selection by explicit artist IDs and by normalized lowercase genres.
- SHUF-002: Custom shuffle settings shall deduplicate artist IDs and genres before persistence.
- SHUF-003: The custom shuffle page shall allow switching between artist selection and genre selection modes.
- SHUF-004: Artist selection shall reuse the same artist catalog and pagination behavior as the Library flow.
- SHUF-005: Genre selection shall derive its options from the loaded artist metadata set.
- SHUF-006: When the user switches into genre mode and the full artist catalog has not been loaded yet, the app shall load all artists to compute the complete genre list.
- SHUF-007: Custom shuffle selection changes shall be persisted with debounce rather than on every tap.
- SHUF-008: Custom shuffle save debounce shall be approximately `350ms`.
- SHUF-009: The custom shuffle page shall support select-all and clear actions for the current mode.
- SHUF-010: The custom shuffle page shall expose explicit empty, disconnected, and no-match states.
- SHUF-011: If custom shuffle is currently the active playback mode, changing custom shuffle settings shall trigger a queue refresh so playback context stays aligned with the saved selection.

## Playback, Queueing, and Transport Control
- PLAY-001: Playback shall be controller-owned and stateful, not delegated to individual pages.
- PLAY-002: The controller shall track current track, position, duration, loading state, buffer ratio, volume, repeat mode, shuffle mode, queue source, output device, bitrate, and stream RTT.
- PLAY-003: Queueing an album shall build a linear album queue unless shuffle mode explicitly redirects playback.
- PLAY-004: Queueing a playlist shall build a playlist-scoped queue and preserve the queue source as playlist.
- PLAY-005: Queueing liked songs shall build a liked-songs queue and preserve the queue source as liked.
- PLAY-006: The app shall support shuffle modes `off`, `all`, `artist`, `album`, `currentPlaylist`, `custom`, and `liked`.
- PLAY-007: Shuffle mode changes shall update visible playback state immediately, even before a new queue is built.
- PLAY-008: Shuffle modes that require additional context shall only start when that context exists.
- PLAY-009: `currentPlaylist` shuffle shall only be startable when playback context is a playlist with a valid playlist ID.
- PLAY-010: `custom` shuffle shall only be startable when at least one artist or genre is selected in custom shuffle settings.
- PLAY-011: `liked` shuffle shall only be startable when liked tracks are available.
- PLAY-012: Resuming playback with no current track while a startable shuffle mode is active shall attempt to seed and play the appropriate shuffle queue.
- PLAY-013: Server shuffle modes shall use server library, playlist, liked, and custom-shuffle data only.
- PLAY-014: Local shuffle modes shall use downloaded-file queues only and shall support downloaded-all, local playlist, and local liked shuffles.
- PLAY-015: Server-only shuffle modes `artist`, `album`, and `custom` shall not be offered for local playback in v1.
- PLAY-016: Repeat mode shall support `off` and `one`.
- PLAY-017: Repeat mode shall be persisted to the server through playback settings.
- PLAY-018: Volume shall be clamped into the range `0.0..1.0`.
- PLAY-019: Volume changes shall take effect immediately in the active audio engine and persist asynchronously with debounce.
- PLAY-020: Volume persistence debounce shall be approximately `350ms`.
- PLAY-021: Selecting an output device shall restart or rebind playback so that the current track continues on the new output path when possible.
- PLAY-022: The output-device list shall always include `System Default` as a stable fallback option.
- PLAY-023: The player shall support seek preview while scrubbing and a debounced seek commit after user input settles.
- PLAY-024: Seek commit debounce shall be approximately `180ms`.
- PLAY-025: Seek completion shall guard against indefinite pending state using an `8s` completion guard.
- PLAY-026: If inline native seek is not available or not accepted, the controller shall restart the current stream from the target playback position.
- PLAY-027: If playback has been manually paused for more than `45s`, resume shall restart the stream instead of assuming the old stream is still valid.
- PLAY-028: Playback position display shall continue to tick locally at approximately `250ms` intervals while playback is active.
- PLAY-029: Auto-advance shall be guarded so scrubbing and track transitions do not trigger duplicate next-track behavior.
- PLAY-030: Stopping playback shall clear active queue state, clear now playing, stop stream monitoring, and shut down the active audio session.
- PLAY-031: The now-playing UI shall expose play/pause, previous, next, stop, shuffle, repeat, stream quality, output device, add-to-playlist, like/unlike, progress, and volume controls.
- PLAY-032: The now-playing UI shall show technical tags for active shuffle mode, repeat-one, bitrate, ping, and queue source when those data are available.
- PLAY-033: The now-playing UI shall expose stream-quality choices `HQ`, `MQ`, and `LQ`, while `AUTO` remains a state label for current mode display.
- PLAY-034: The progress bar shall visualize both current playback position and buffered position.
- PLAY-035: The compact mobile now-playing surface shall still allow expansion into the full transport experience.
- PLAY-036: Adding the currently playing track to a playlist shall be possible directly from now-playing controls.
- PLAY-037: The controller shall push OS-level now-playing updates so native transport surfaces stay synchronized with Flutter state.
- PLAY-038: The controller shall queue and play local playlists and local liked downloads using downloaded files rather than server streams.
- PLAY-039: Downloaded-file playback shall load audio through a platform-aware local source that reads seekable byte ranges in bounded chunks before falling back to direct file access.

## Network and Server Contract
- NET-001: The client shall treat the canonical API base as a URL ending in `/api/v1`.
- NET-002: When given a raw host or root URL, the client shall normalize it to `/api/v1` before storing it as the active base URL.
- NET-003: Server probing shall accept either the root `/health` endpoint or the `/api/v1/health` endpoint as a successful connection target.
- NET-004: Server login shall use `POST /auth/login` and shall require a non-empty `token` in the response payload.
- NET-005: Artist browsing shall use `GET /browse/artists?limit={limit}&offset={offset}`.
- NET-006: Artist-detail album loading shall use `GET /browse/artists/{artistId}/albums`.
- NET-007: Album-track loading shall use `GET /browse/albums/{albumId}/tracks`.
- NET-008: Playlist listing shall use `GET /library/playlists`.
- NET-009: Playlist-track loading shall use `GET /browse/playlists/{playlistId}/tracks`.
- NET-010: Liked-track loading shall use `GET /browse/likes`.
- NET-011: Library shuffle queue retrieval shall use `GET /library/shuffle` with `mode` and optional `artist_id`, `album_id`, `artist_ids`, and `genres` query parameters.
- NET-012: Statistics retrieval shall use `GET /stats` with optional `year` and `month` parameters.
- NET-013: Search shall use `GET /library/search?query={query}&limit=50`.
- NET-014: Search-kind filtering shall currently occur client-side after the server returns results.
- NET-015: Album lookup shall use `GET /library/albums/{albumId}`.
- NET-016: Artist lookup shall use `GET /browse/artists/{artistId}`.
- NET-017: Track lookup shall use `GET /browse/tracks/{trackId}`.
- NET-018: Like operations shall use `POST /library/likes/{trackId}` and unlike operations shall use `DELETE /library/likes/{trackId}`.
- NET-019: Playlist creation shall use `POST /library/playlists`.
- NET-020: Playlist rename and playlist track replacement shall both use `POST /library/playlists/{playlistId}` with different payload shapes.
- NET-021: Playlist deletion shall use `DELETE /library/playlists/{playlistId}`.
- NET-022: Playback settings retrieval and update shall use `/player/settings`.
- NET-023: Server port discovery shall use `/server/ports`.
- NET-024: Album cover URLs shall resolve to `/library/albums/{albumId}/cover`.
- NET-025: Artist cover URLs shall resolve to `/library/artists/{artistId}/cover`, with optional `kind` for logo/banner selection.
- NET-026: Authorization shall use a bearer token when available and omit the header when no token exists.
- NET-027: Default API request timeout shall be `8s`.
- NET-028: Health-check timeout shall be `2s`.
- NET-029: Retryable GET-like requests shall allow up to `3` attempts.
- NET-030: Retry behavior shall cover timeouts, socket/client transport errors, and retryable `5xx` responses.
- NET-031: Retry delays shall be backoff-based and jittered rather than fixed.
- NET-032: Health ping logic shall be able to report round-trip time in milliseconds for diagnostics and UI display.
- NET-033: Download metadata hydration shall use protected `GET /library/tracks/{trackId}/offline-metadata` and parse track, album, artist, and schema-version fragments.
- NET-034: Batch download preparation shall use protected `POST /download/batches` with `track_ids` and optional `client_batch_id`.
- NET-035: Batch download manifests shall parse schema version, batch ID, created timestamp, download items, unavailable track IDs, offline metadata fragments, byte length, content type, ETag, and SHA256 fields.
- NET-036: Resumed file downloads shall send `Range` and `If-Range` when a partial file and ETag are available.
- NET-037: Offline artwork hydration shall use protected album and artist cover endpoints to fetch album cover bytes plus artist logo and banner bytes when those IDs are available.

## Persistence and Local State
- DATA-001: Saved credentials shall persist to `auth.json` outside the app bundle on non-web platforms.
- DATA-002: On Windows, saved credentials and playback preferences shall prefer `APPDATA\\Phonolite`.
- DATA-003: On non-Windows native platforms, saved credentials and playback preferences shall prefer the application support directory under `Phonolite`.
- DATA-004: Playback preferences shall persist to `playback_prefs.json`.
- DATA-005: Playback preferences shall currently include volume and collection-list-mode.
- DATA-006: Custom shuffle settings shall persist to `shuffle_settings.json`.
- DATA-007: Custom shuffle settings shall prefer an application cache directory when available and fall back to support directories when cache storage is unavailable.
- DATA-008: Persistence helpers shall be effectively disabled on web targets.
- DATA-009: App diagnostics shall remain in memory rather than in a persisted log file.
- DATA-010: The in-memory log buffer shall keep up to `3000` entries and trim in chunks of `500` when capacity is exceeded.
- DATA-011: Offline track metadata, source track aliases, local liked downloads, local playlists, and local playlist membership shall persist in `phonolite_offline.sqlite` under the existing offline storage root.
- DATA-012: Existing `offline_library.json` download indexes shall be migrated into the SQLite offline database on first database open.
- DATA-013: Downloaded tracks from different servers shall merge into one canonical local track when normalized artist, album, and title match and duration differs by no more than `2s`.
- DATA-014: Downloaded tracks shall remain separate local tracks when their normalized metadata differs or their duration differs by more than `2s`.
- DATA-015: Source-track records shall keep server base URL, server track ID, local track ID, download status, paths, byte progress, content type, etag, and error details.
- DATA-016: Local likes shall accept only local track IDs that have at least one completed downloaded source file.
- DATA-017: Local playlist membership shall accept only local track IDs that have at least one completed downloaded source file.
- DATA-018: Removing or losing a completed download shall prune unavailable local likes and local playlist membership.
- DATA-019: Web shall remain unsupported for offline persistence and shall return empty offline/local-user datasets.
- DATA-020: Offline storage location preferences shall persist outside the offline metadata/download directories so that changing those directories does not lose the path settings.
- DATA-021: The offline metadata directory shall contain `phonolite_offline.sqlite` and the migrated `offline_library.json` index when present.
- DATA-022: The offline downloads directory shall contain per-server downloaded audio files and partial download files.
- DATA-023: The app shall allow the metadata directory and downloads directory to be reset independently to the default offline storage root.
- DATA-024: Offline download statuses shall include queued, preparing, downloading, paused, validating, downloaded, failed, corrupt, and canceled.
- DATA-025: Offline download batches and items shall persist in SQLite so queued, paused, failed, corrupt, and completed work survives app restarts.
- DATA-026: The download scheduler shall run at most three active downloads for the currently connected server.
- DATA-027: Logout, authorization loss, or disconnect from the current server shall pause queued or active downloads for that server while keeping partial files.
- DATA-028: Reconnecting to the same server with a valid session shall resume paused downloads for that server.
- DATA-029: Partial downloads shall resume with server ETag validation, and completed files shall be promoted only after byte-count and SHA256 validation pass when manifest validation data is present.
- DATA-030: Corrupt, failed, canceled, partial, and completed downloads shall be removable from the Download Manager, and removing completed downloads shall prune local likes and local playlist membership only when no completed local source remains for the canonical track.
- DATA-031: The offline metadata store shall persist local album cover, artist logo, and artist banner file paths on canonical tracks and store fetched artwork under the metadata directory.

## Diagnostics, Health, and Error Handling
- DIAG-001: The controller shall log informational, status, warning, error, and debug messages through a shared application logger.
- DIAG-002: The UI shall expose current log history through a dedicated logs screen.
- DIAG-003: The controller shall periodically poll server health when not actively playing.
- DIAG-004: Health-monitor polling cadence shall be approximately `12s` while idle.
- DIAG-005: Health polling shall update stream-connected state and ping latency in the playback model.
- DIAG-006: The audio engine shall report QUIC transport stats and RTT when available.
- DIAG-007: The controller shall warn when iOS playback appears to target loopback hosts that may not be reachable as expected from device runtime conditions.
- DIAG-008: Native and FFI errors shall be surfaced back into Dart as readable error strings rather than swallowed silently.

## Native Audio Engine and Playback Pipeline
- AUDIO-001: The audio engine shall run playback work in a dedicated isolate worker rather than on the main UI isolate.
- AUDIO-002: The playback engine shall support platform-specific native audio players for Android, Windows, and Apple platforms.
- AUDIO-003: The playback engine shall support Opus decode and QUIC transport through bundled FFI packages rather than through pure Dart decode/transport.
- AUDIO-004: The playback engine shall support stream settings for mode, quality, and frame duration.
- AUDIO-005: The playback engine shall support pause, resume, stop, set-volume, set-output-device, and seek commands from the controller.
- AUDIO-006: The playback engine shall support inline seek when the native transport/player path can honor it.
- AUDIO-007: Playback buffering shall adapt based on whether the host appears to be loopback/local versus remote and on measured RTT.
- AUDIO-008: The playback engine shall report playback progress, buffered ratio, bitrate, and RTT back to the controller.
- AUDIO-009: The playback engine shall periodically send playback progress and buffer statistics back over QUIC while streaming.
- AUDIO-010: The playback engine shall tolerate temporary queue-full conditions in native audio outputs and continue pumping once capacity is available.
- AUDIO-011: The raw Opus stream format shall use a custom header with magic `OPUSR01\0`.
- AUDIO-012: Raw Opus header parsing shall reject unknown header versions, truncated headers, invalid lengths, and zero-channel payloads.
- AUDIO-013: The Opus decoder shall support sample rates `8000`, `12000`, `16000`, `24000`, and `48000`.
- AUDIO-014: The Opus decoder shall expose a maximum frame size of `5760`.
- AUDIO-015: QUIC transport shall use ALPN `phonolite-quic`.
- AUDIO-016: QUIC transport shall authenticate immediately after connect by sending a token-bearing control message.
- AUDIO-017: QUIC transport shall support control messages for open, buffer, playback stats, seek, advance, and ping.
- AUDIO-018: QUIC transport shall maintain a dedicated control stream and separate audio payload streams.
- AUDIO-019: QUIC transport shall buffer pending non-active streams temporarily but shall avoid mixing prefetched audio into the active stream.
- AUDIO-020: QUIC transport shall ping approximately every `500ms` and send ack-eliciting traffic approximately every `200ms`.
- AUDIO-021: QUIC transport shall use a `30s` idle timeout.
- AUDIO-022: QUIC transport shall currently disable peer certificate verification.
- AUDIO-023: QUIC transport shall maintain a pending-prefetch cap of roughly `12MB`.
- AUDIO-024: Local downloaded media playback shall choose platform-specific chunk sizes for desktop, Android, and Apple targets when streaming file bytes into the player backend.

## Android Platform Requirements
- AND-001: Android shall use a shared `FlutterEngine` created at the application level so the main activity and media service can communicate through the same Dart runtime.
- AND-002: The Android activity shall reuse the shared engine and shall not destroy it when the host activity is destroyed.
- AND-003: Android shall declare permissions for internet access, network-state access, wake lock, notifications, foreground service, and media playback foreground service.
- AND-004: Android shall allow cleartext traffic.
- AND-005: Android shall expose an automotive media capability through `automotive_app_desc.xml`.
- AND-006: Android shall provide a `MediaBrowserServiceCompat` implementation for media notifications and vehicle integrations.
- AND-007: Android media notifications shall show previous, play/pause, next, and like/unlike actions.
- AND-008: Android media notifications shall start as a foreground service when active playback metadata exists.
- AND-009: Android media transport callbacks shall forward play, pause, next, previous, seek, and like commands back into Flutter through the platform bridge.
- AND-010: Android shall provide browseable vehicle roots for Home, Artists, Playlists, and Liked Songs when authorized and data is available.
- AND-011: Android vehicle browsing shall expose artist-to-album drilldown and direct playlist or liked-song playback actions.
- AND-012: Android shall provide home-level vehicle actions for library shuffle, liked shuffle, and custom shuffle.
- AND-013: Android audio output shall use `AudioTrack` in stream mode with low-latency performance mode when supported.
- AND-014: Android audio output shall request audio focus before playback and abandon focus after the last output session closes.
- AND-015: Android audio output shall pause playback when audio focus is lost or when the route becomes noisy.
- AND-016: Android shall enumerate available output devices through `AudioManager.getDevices()` and expose friendly route names.
- AND-017: Android output-device selection shall attempt to bind `AudioTrack` to the selected preferred device when supported by the API level.

## iOS Platform Requirements
- IOS-001: iOS shall configure `AVAudioSession` for playback mode with AirPlay and Bluetooth A2DP allowed.
- IOS-002: iOS shall activate the audio session during startup and again when resuming native playback queues.
- IOS-003: iOS shall pause Flutter playback when the audio session is interrupted or when the previous audio route becomes unavailable.
- IOS-004: iOS shall publish now-playing metadata through `MPNowPlayingInfoCenter`.
- IOS-005: iOS shall handle remote play, pause, toggle, next, and previous commands through `MPRemoteCommandCenter`.
- IOS-006: iOS shall keep remote seek-position change disabled in the current implementation.
- IOS-007: iOS shall support background audio mode.
- IOS-008: iOS shall allow arbitrary transport security loads in the current implementation.
- IOS-009: iOS shall declare local-network usage text and Bonjour service `_phonolite._tcp`.
- IOS-010: iOS shall actively probe local-network permission state using `NWListener` and cache the resulting status.
- IOS-011: iOS shall expose local-network permission state, refresh, and settings-opening hooks to Flutter through the `phonolite/permissions` channel.
- IOS-012: The login UI shall show an iOS-only local-network permission warning when the permission state is denied or unknown.
- IOS-013: iOS shall support CarPlay through a dedicated `CPTemplateApplicationScene`.
- IOS-014: CarPlay shall present a logged-out root prompting the user to open the phone app when authorization is missing.
- IOS-015: Authorized CarPlay shall present Home and Library root tabs.
- IOS-016: CarPlay Home shall expose shuffle-related actions sourced from Flutter.
- IOS-017: CarPlay Library shall expose Artists, Playlists, and Liked Songs, with artist-to-album drilldown.
- IOS-018: CarPlay shall support direct play commands for liked songs, albums, playlists, and home actions.
- IOS-019: CarPlay shall maintain a now-playing list item and a like/unlike now-playing button when a track is available.
- IOS-020: iOS native audio output shall currently rely on `AudioQueue` and shall not expose manual output-device enumeration from the provided iOS C bridge.

## macOS Platform Requirements
- MAC-001: macOS shall launch into a Flutter window managed by `MainFlutterWindow`.
- MAC-002: macOS shall terminate the app after the last window closes.
- MAC-003: macOS shall declare support for secure restorable state.
- MAC-004: macOS shall allow arbitrary transport security loads in the current implementation.
- MAC-005: macOS native audio output shall use `AudioQueue`.
- MAC-006: macOS native audio output shall support selecting a CoreAudio output device by device ID.
- MAC-007: macOS shall enumerate output-capable audio devices through CoreAudio and expose user-readable device names to Flutter.

## Windows Platform Requirements
- WIN-001: Windows shall package the app as a native desktop window with the on-disk name `Phonolite`.
- WIN-002: Windows shall create the main window at approximately `1280x720` on startup.
- WIN-003: Windows shall install generated native assets beside the executable at build/install time.
- WIN-004: Windows runner code shall support dark non-client decorations when the OS theme prefers dark mode.
- WIN-005: Windows native audio output shall be available through the platform-specific player path in the Flutter audio engine.
- WIN-006: Windows shall enumerate output devices through the waveOut API and support selecting a device ID or the default mapper.
- WIN-007: Windows-specific UI code shall continue to avoid backdrop blur and image precaching.
- WIN-008: Windows local-file playback shall use a vendored `just_audio_windows` patch that posts event and data channel emissions onto the Flutter window thread before touching platform-channel event sinks.

## Constraints and Current Implementation Limits
- LIM-001: The current vehicle integrations browse only to album or playlist playback entry points; they do not expose deep per-track browsing UIs.
- LIM-002: The current iOS native C audio bridge exposes playback control but not discrete manual output-device selection.
- LIM-003: Search-kind filtering is currently enforced client-side after the search response is returned.
- LIM-004: QUIC peer verification is currently disabled, so the present transport assumes a trusted environment rather than verified server identity.
- LIM-005: HTTP cleartext traffic is currently allowed on Android, iOS, and macOS.
- LIM-006: Persisted auth, playback preferences, and custom shuffle settings are intentionally inactive on web targets.
- LIM-007: Local offline persistence remains intentionally inactive on web targets.

## Suggested Next Traceability Layer
- TRACE-001: Future feature work should link new issues, tests, and design changes back to these requirement IDs.
- TRACE-002: If this file becomes too large to manage comfortably, the next split should separate shell/auth, library/features, playback/transport, and platform-specific requirements into dedicated documents while preserving the same IDs.
