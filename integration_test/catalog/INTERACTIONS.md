# On-screen interaction inventory

241 source-audited interaction patterns across 12 feature catalogs. 61 patterns have a device journey; that is implementation coverage, not proof that they ran on a phone.

22 patterns also link to the separate opt-in playback-changing suite. Run it with `bash tools/ui_tests/run_player_controls.sh DEVICE_ID`; those actions do not run in the ordinary UI suite.

Each row is an interaction pattern, reused for every track/album/artist/playlist. Local/server, empty/populated, loading/disabled and compact/wide variations require their own device/data coverage. Native UI and source-only pages are explicitly marked. The inventory is source-audited, not a claim that every runtime state was visited.

Edit the feature JSON files, implement journeys under `../journeys/`, then regenerate with `python3 tools/ui_tests/catalog.py` from the app directory. Run `flutter test test/ui_automation` to validate references.

## Artist Album

Sources: [lib/pages/artist_detail_screen.dart](../../lib/pages/artist_detail_screen.dart), [lib/pages/local_artist_detail_screen.dart](../../lib/pages/local_artist_detail_screen.dart), [lib/pages/album_detail_screen.dart](../../lib/pages/album_detail_screen.dart), [lib/pages/local_album_detail_screen.dart](../../lib/pages/local_album_detail_screen.dart), [lib/widgets/display/artist_hero.dart](../../lib/widgets/display/artist_hero.dart), [lib/widgets/display/album_hero.dart](../../lib/widgets/display/album_hero.dart)

| ID | Visible action | Expected outcome | Available when | Effect | Device journey |
| --- | --- | --- | --- | --- | --- |
| artist.back | Tap Back to library | Return to originating library/detail route | Artist detail | browse | library.artist_navigation, library.album_navigation |
| artist.scroll | Scroll artist releases and credits | Show further albums, collaborations, appearances and credits | Artist detail | browse | Pending / prerequisite-specific |
| artist.about | Expand/collapse About artist | Reveal/hide compact artist metadata | Metadata available | browse | Pending / prerequisite-specific |
| artist.summary | Tap Read more or Collapse | Expand/collapse long biography | Wide desktop layout; phone uses expandable metadata instead | browse | Pending / prerequisite-specific |
| artist.album_open | Tap album card or row | Open selected local/server album | Album loaded | browse | library.album_navigation |
| artist.collaboration_open | Tap collaboration/appearance/credit release | Open matching release without losing return path | Matching release loaded | browse | Pending / prerequisite-specific |
| artist.collection_view | Switch release cards/list | Change and retain shared collection layout | Artist detail | preference | Pending / prerequisite-specific |
| artist.download_open | Tap Download artist | Open confirmation with download plan | Connected artist | browse | Pending / prerequisite-specific |
| artist.download_confirm | Confirm artist download | Queue eligible artist albums | Connected artist | mutation | Pending / prerequisite-specific |
| artist.edit | Tap Edit | Select downloaded albums for removal | Downloaded albums | browse | Pending / prerequisite-specific |
| artist.select_album | Toggle album checkbox | Change selected albums | Selection mode | browse | Pending / prerequisite-specific |
| artist.select_all | Select all or Deselect all albums | Update eligible selection | Selection mode | browse | Pending / prerequisite-specific |
| artist.remove_selected | Tap Remove selected | Show confirmation for downloaded albums | Selection exists | browse | Pending / prerequisite-specific |
| artist.cancel_selection | Cancel album selection | Return to artist without deletion | Selection mode | browse | Pending / prerequisite-specific |
| album.back | Tap Back to artist | Return to preceding route | Album detail | browse | library.album_navigation |
| album.scroll | Scroll album track list | Reveal further tracks | Enough tracks | browse | Pending / prerequisite-specific |
| album.details | Expand/collapse Album details | Reveal/hide compact album metadata | Metadata available | browse | Pending / prerequisite-specific |
| album.summary | Tap Read more or Collapse | Expand/collapse album summary | Wide desktop layout; phone uses expandable metadata instead | browse | Pending / prerequisite-specific |
| album.play | Tap Play album | Start first track with the album queue | Playable album | playback | Pending / prerequisite-specific |
| album.download_open | Tap album download action | Queue missing album downloads directly; no confirmation modal | Connected album | browse | Pending / prerequisite-specific |
| album.download_confirm | Confirm album download | No confirmation control is mounted; retained as an audit note | Not present in current UI; album downloads queue directly | mutation | Pending / prerequisite-specific |
| album.edit | Tap Edit tracks | Enter downloaded-track selection | Downloaded tracks | browse | Pending / prerequisite-specific |
| album.select_track | Tap track/checkbox in selection mode | Toggle selected track | Selection mode | browse | Pending / prerequisite-specific |
| album.select_all | Select all or Deselect all tracks | Update eligible track selection | Selection mode | browse | Pending / prerequisite-specific |
| album.remove_selected | Tap Remove selected | Show download-removal confirmation | Selection exists | browse | Pending / prerequisite-specific |
| album.cancel_selection | Cancel track selection | Exit without removing downloads | Selection mode | browse | Pending / prerequisite-specific |

## Authentication

Sources: [lib/pages/login_page.dart](../../lib/pages/login_page.dart), [lib/pages/reset_user_password_page.dart](../../lib/pages/reset_user_password_page.dart)

| ID | Visible action | Expected outcome | Available when | Effect | Device journey |
| --- | --- | --- | --- | --- | --- |
| authentication.address | Enter Server address | Update server host draft | Connect page | browse | Pending / prerequisite-specific |
| authentication.port | Enter Port | Update server port draft | Connect page | browse | Pending / prerequisite-specific |
| authentication.connect | Tap Connect or submit port | Check server and open sign-in form on success | Valid address | network | Pending / prerequisite-specific |
| authentication.username | Enter Username | Update sign-in draft | Server reachable | browse | Pending / prerequisite-specific |
| authentication.password | Enter Password | Update obscured sign-in draft | Server reachable | browse | Pending / prerequisite-specific |
| authentication.remember | Toggle Remember me | Choose session persistence for sign-in | Sign-in form | browse | Pending / prerequisite-specific |
| authentication.submit | Tap Sign in or submit password | Authenticate and return to app on success | Test account | mutation | Pending / prerequisite-specific |
| authentication.change_server | Tap Change server | Return to address form | Sign-in form | browse | Pending / prerequisite-specific |
| authentication.dismiss_keyboard | Tap page background | Dismiss keyboard | Input focused | browse | Pending / prerequisite-specific |
| authentication.ios_settings | Tap Open iOS Settings | Open system settings for local-network permission | iOS permission not granted | native | Pending / prerequisite-specific |
| authentication.back | Tap Back to settings | Return from connection flow | Connect/sign-in page | browse | Pending / prerequisite-specific |
| password.current | Enter Current password | Update obscured draft | Password page | browse | Pending / prerequisite-specific |
| password.new | Enter New password | Update obscured draft | Password page | browse | Pending / prerequisite-specific |
| password.confirm | Enter Confirm new password | Update confirmation draft | Password page | browse | Pending / prerequisite-specific |
| password.submit | Tap Reset password or submit final field | Validate fields and change account password | Disposable test account | mutation | Pending / prerequisite-specific |
| password.done | Tap Done after success | Return to Settings | Password changed | browse | Pending / prerequisite-specific |
| password.back | Tap Back to settings | Leave password form | Password page | browse | Pending / prerequisite-specific |
| password.dismiss_keyboard | Tap background | Dismiss keyboard | Input focused | browse | Pending / prerequisite-specific |

## Downloads

Sources: [lib/widgets/modals/download_manager_panel.dart](../../lib/widgets/modals/download_manager_panel.dart), [lib/widgets/modals/remove_download_modal.dart](../../lib/widgets/modals/remove_download_modal.dart), [lib/widgets/display/download_selection_toolbar.dart](../../lib/widgets/display/download_selection_toolbar.dart)

| ID | Visible action | Expected outcome | Available when | Effect | Device journey |
| --- | --- | --- | --- | --- | --- |
| downloads.open | Tap Download Manager | Show queue and cache status | all | browse | library.download_manager |
| downloads.scroll | Scroll jobs/cache rows | Reveal remaining jobs/files | Enough entries | browse | Pending / prerequisite-specific |
| downloads.pause_all | Tap Pause all | Pause pausable jobs | Pausable jobs | mutation | Pending / prerequisite-specific |
| downloads.resume_all | Tap Resume paused | Resume paused jobs | Paused jobs | mutation | Pending / prerequisite-specific |
| downloads.clear_open | Tap Clear all jobs and cache | Show clear confirmation | Jobs/cache exist | browse | Pending / prerequisite-specific |
| downloads.clear_confirm | Confirm clear | Remove jobs and temporary cache | Disposable download state | mutation | Pending / prerequisite-specific |
| downloads.clear_cancel | Cancel clear | Keep jobs/cache | Confirmation open | browse | Pending / prerequisite-specific |
| downloads.job_pause | Tap Pause download job | Pause one job | Pausable job | mutation | Pending / prerequisite-specific |
| downloads.job_resume | Tap Resume download job | Resume one job | Paused job | mutation | Pending / prerequisite-specific |
| downloads.job_cancel | Tap Cancel and remove job | Cancel/remove selected job | Disposable job | mutation | Pending / prerequisite-specific |
| downloads.track_actions | Open Track actions for failed item | Show retry action | Failed download | browse | Pending / prerequisite-specific |
| downloads.retry | Tap Retry or Retry download | Retry eligible failed download | Failed download | mutation | Pending / prerequisite-specific |
| downloads.remove_open | Request download removal | Show target/count confirmation | Downloaded selection | browse | Pending / prerequisite-specific |
| downloads.remove_confirm | Tap Remove in confirmation | Delete local audio and unused metadata/artwork | Disposable download | mutation | Pending / prerequisite-specific |
| downloads.remove_cancel | Tap Cancel or dismiss confirmation | Retain downloaded files | Confirmation open | browse | Pending / prerequisite-specific |
| downloads.close | Tap Close, dismiss barrier, or drag supported sheet | Return to underlying page | Manager open | browse | library.download_manager |

## Library

Sources: [lib/pages/library_page.dart](../../lib/pages/library_page.dart), [lib/widgets/inputs/search_hud.dart](../../lib/widgets/inputs/search_hud.dart), [lib/widgets/layout/search_results_sliver.dart](../../lib/widgets/layout/search_results_sliver.dart)

| ID | Visible action | Expected outcome | Available when | Effect | Device journey |
| --- | --- | --- | --- | --- | --- |
| library.scroll | Scroll artists and downloaded music down/up | Content moves and remains hittable | Enough content to scroll | browse | library.scroll |
| library.search_focus | Tap library search | Field receives focus and keyboard opens | all | browse | library.search |
| library.search_type | Enter or edit search text | Local/server results reflect the query | all | browse | library.search |
| library.search_submit | Press keyboard Search | Submit current query | all | browse | library.search |
| library.search_clear | Tap Clear search | Empty query and restore catalog | all | browse | library.search |
| library.search_dismiss | Drag list while keyboard is visible | Dismiss keyboard without losing query | all | browse | Pending / prerequisite-specific |
| library.collection_view | Tap Show list or Show cards | Switch collection layout and retain preference | all | preference | library.collection_view |
| library.refresh | Tap Refresh library | Refresh catalog and expose busy/error state | all | network | Pending / prerequisite-specific |
| library.artist_open | Tap an artist card or row | Open local/server artist details | Artist loaded | browse | library.artist_navigation, library.album_navigation |
| library.result_artist | Tap an artist search result | Open matching artist | Artist search result | browse | Pending / prerequisite-specific |
| library.result_album | Tap an album search result | Open matching album | Album search result | browse | Pending / prerequisite-specific |
| library.result_track | Tap a track search result | Start corresponding playback | Track search result | playback | Pending / prerequisite-specific |
| library.result_actions | Open search-result Track actions | Show available track actions | Track search result | browse | Pending / prerequisite-specific |
| library.edit | Tap Edit | Enter downloaded-artist selection | Downloaded artists | browse | Pending / prerequisite-specific |
| library.select_artist | Tap artist or checkbox in selection mode | Toggle selected artist | Selection mode | browse | Pending / prerequisite-specific |
| library.select_all | Tap Select all or Deselect all | Select all eligible artists or clear selection | Selection mode | browse | Pending / prerequisite-specific |
| library.remove_selected | Tap Remove selected | Open download-removal confirmation | Selection exists | browse | Pending / prerequisite-specific |
| library.cancel_selection | Tap Cancel | Exit selection and retain downloaded files | Selection mode | browse | Pending / prerequisite-specific |

## Liked

Sources: [lib/pages/liked_page.dart](../../lib/pages/liked_page.dart), [lib/widgets/display/track_row_tile.dart](../../lib/widgets/display/track_row_tile.dart)

| ID | Visible action | Expected outcome | Available when | Effect | Device journey |
| --- | --- | --- | --- | --- | --- |
| liked.scroll | Scroll local/server liked tracks | Reveal more liked tracks | Enough liked tracks | browse | liked.scroll |
| liked.play | Tap liked track | Play appropriate local/server liked queue | Liked track | playback | Pending / prerequisite-specific |
| liked.unlike | Tap Unlike | Remove track from appropriate liked list | Liked track | mutation | Pending / prerequisite-specific |
| liked.add_to_playlist | Tap Add to playlist | Open scoped chooser | Liked track | browse | Pending / prerequisite-specific |
| liked.download | Use track download action | Queue track download | Server liked track | mutation | Pending / prerequisite-specific |
| liked.edit | Tap Edit tracks | Enter downloaded-track selection | Downloaded liked tracks | browse | Pending / prerequisite-specific |
| liked.long_press | Long-press downloaded liked track | Select it and enter edit mode | Downloaded liked track | browse | Pending / prerequisite-specific |
| liked.select | Toggle a track checkbox | Change removal selection | Selection mode | browse | Pending / prerequisite-specific |
| liked.select_all | Select all or Deselect all | Update downloaded-track selection | Selection mode | browse | Pending / prerequisite-specific |
| liked.remove_selected | Remove selected downloads | Confirm and remove local downloaded files | Selected downloads | mutation | Pending / prerequisite-specific |
| liked.cancel_selection | Tap Cancel | Exit selection without removal | Selection mode | browse | Pending / prerequisite-specific |

## Navigation

Sources: [lib/pages/home_page.dart](../../lib/pages/home_page.dart), [lib/widgets/navigation/adaptive_scaffold.dart](../../lib/widgets/navigation/adaptive_scaffold.dart)

| ID | Visible action | Expected outcome | Available when | Effect | Device journey |
| --- | --- | --- | --- | --- | --- |
| navigation.library | Tap Library | Show Library and retain its navigation stack | all | browse | navigation.primary_tabs |
| navigation.playlists | Tap Playlists | Show Playlists and retain its navigation stack | all | browse | navigation.primary_tabs |
| navigation.liked | Tap Liked | Show Liked Tracks | all | browse | navigation.primary_tabs |
| navigation.stats | Tap Stats | Show Listening Statistics | Statistics enabled | browse | navigation.stats_tab |
| navigation.settings | Tap Settings | Show Settings | all | browse | navigation.primary_tabs |
| navigation.tab_pairs | Switch between every ordered pair of tabs | Destination remains usable and no Flutter exception occurs | all | browse | navigation.ordered_tab_pairs |
| navigation.tab_history | Open a detail screen then switch away and back | Selected tab retains its detail route | Loaded catalog | browse | Pending / prerequisite-specific |
| navigation.system_back | Use system back or supported route-back gesture | Return one route without leaving the app unexpectedly | Platform-dependent back support | browse | Pending / prerequisite-specific |

## Player

Sources: [lib/widgets/display/now_playing_bar.dart](../../lib/widgets/display/now_playing_bar.dart), [lib/widgets/modals/device_picker_modal.dart](../../lib/widgets/modals/device_picker_modal.dart), [lib/widgets/inputs/local_server_toggle.dart](../../lib/widgets/inputs/local_server_toggle.dart)

| ID | Visible action | Expected outcome | Available when | Effect | Device journey |
| --- | --- | --- | --- | --- | --- |
| player.expand | Tap mini-player body | Open expanded player | Compact/mobile layout | browse | player.tray_transition, Opt-in playback: audio.expand |
| player.swipe_close | Drag expanded player down | Dismiss tray and return to underlying page | Expanded player | browse | player.tray_transition, Opt-in playback: audio.dismiss |
| player.open_details | Tap playback artwork/artist-album/source link | Navigate to the playing album or playlist | Resolvable playback source | browse | Opt-in playback: audio.artwork_details |
| player.play_pause | Tap Play/Pause | Start/resume or pause playback | Enabled transport | playback | Opt-in playback: audio.mini_pause, Opt-in playback: audio.mini_resume, Opt-in playback: audio.expanded_pause, Opt-in playback: audio.expanded_resume |
| player.next | Tap Next song | Advance queue | Enabled queue | playback | Opt-in playback: audio.mini_next |
| player.previous | Tap Previous | Restart/return to preceding track | Enabled queue | playback | Opt-in playback: audio.expanded_previous |
| player.stop | Tap Stop where present | Stop playback | Layout exposing Stop | playback | Opt-in playback: audio.stop_button |
| player.seek | Tap/drag/release progress slider | Preview then commit seek within track duration | Track loaded | playback | Opt-in playback: audio.slider_forward, Opt-in playback: audio.slider_backward |
| player.repeat | Tap repeat control | Toggle repeat behavior | Player visible | preference | Opt-in playback: audio.repeat_button |
| player.like | Tap Like/Unlike | Update current track's local/server liked state | Track loaded | mutation | Opt-in playback: audio.like_button |
| player.add_to_playlist | Tap playlist-add control | Open chooser for current track | Track loaded | browse | Opt-in playback: audio.playlist_button |
| player.volume | Adjust volume slider | Update playback volume | Layout exposing volume | preference | Opt-in playback: audio.volume_slider |
| player.tags_scroll | Scroll clipped playback tags horizontally | Reveal overflow source/format tags | Overflowing tags | browse | Pending / prerequisite-specific |
| shuffle.open | Tap shuffle control | Show mode choices without changing mode | all | browse | player.shuffle_dialog, Opt-in playback: audio.shuffle_button |
| shuffle.scope | Tap Local or Server | Change shuffle scope and restore scoped mode | Shuffle dialog | playback | Pending / prerequisite-specific |
| shuffle.off | Select Off | Disable shuffle for selected scope | Shuffle dialog | preference | Opt-in playback: audio.shuffle_button |
| shuffle.library | Select Whole Library | Start/apply library shuffle | Eligible library | playback | Pending / prerequisite-specific |
| shuffle.artist | Select Current Artist | Apply artist shuffle | Eligible current artist | playback | Pending / prerequisite-specific |
| shuffle.album | Select Current Album | Apply album shuffle | Eligible current album | playback | Opt-in playback: audio.shuffle_button |
| shuffle.playlist | Select Current Playlist | Apply playlist shuffle | Playlist queue | playback | Pending / prerequisite-specific |
| shuffle.custom | Select Custom | Apply configured artist/genre shuffle | Configured selections | playback | Pending / prerequisite-specific |
| shuffle.liked | Select Liked | Apply liked-track shuffle | Liked tracks | playback | Pending / prerequisite-specific |
| shuffle.close | Tap Close or dismiss | Keep current shuffle mode | Shuffle dialog | browse | player.shuffle_dialog |
| quality.open | Tap stream-quality badge | Open Stream Quality | Server track | browse | Opt-in playback: audio.quality_low, Opt-in playback: audio.quality_medium, Opt-in playback: audio.quality_high |
| quality.high | Select HQ | Update streaming preference | Quality dialog | preference | Opt-in playback: audio.quality_high |
| quality.medium | Select MQ | Update streaming preference | Quality dialog | preference | Opt-in playback: audio.quality_medium |
| quality.low | Select LQ | Update streaming preference | Quality dialog | preference | Opt-in playback: audio.quality_low, Opt-in playback: audio.quality_while_paused |
| quality.close | Tap Close or dismiss | Keep quality preference | Quality dialog | browse | Pending / prerequisite-specific |
| output.open | Tap output speaker | Open Select output device | all | browse | player.output_dialog, Opt-in playback: audio.output_button |
| output.refresh | Tap Refresh | Reload native output list | Output dialog | browse | Opt-in playback: audio.output_button |
| output.select | Tap output device | Switch selected output | Device available | playback | Opt-in playback: audio.output_button |
| output.close | Tap Close or dismiss | Keep selected output | Output dialog | browse | player.output_dialog |

## Playlists

Sources: [lib/pages/playlists_page.dart](../../lib/pages/playlists_page.dart), [lib/pages/playlist_detail_view.dart](../../lib/pages/playlist_detail_view.dart), [lib/widgets/modals/playlist_editor_modal.dart](../../lib/widgets/modals/playlist_editor_modal.dart), [lib/widgets/display/playlist_module_card.dart](../../lib/widgets/display/playlist_module_card.dart)

| ID | Visible action | Expected outcome | Available when | Effect | Device journey |
| --- | --- | --- | --- | --- | --- |
| playlists.scroll | Scroll playlist collections | Reveal additional playlists | Enough playlists | browse | playlists.scroll |
| playlists.create_open | Tap Create playlist | Open empty editor | all | browse | playlists.create_cancel |
| playlists.collection_view | Tap Show cards or Show list | Switch shared collection layout | all | preference | playlists.collection_view |
| playlists.open | Tap a playlist card/row | Open local/server playlist detail | Playlist exists | browse | playlists.detail_navigation |
| playlists.long_press | Long-press populated playlist | Start playlist from top | Populated playlist | playback | Pending / prerequisite-specific |
| playlists.edit | Tap Edit playlists | Enter playlist selection | Playlist exists | browse | Pending / prerequisite-specific |
| playlists.select | Tap playlist/checkbox in selection mode | Toggle selected playlist | Selection mode | browse | Pending / prerequisite-specific |
| playlists.select_all | Select all or Deselect all playlists | Update selection | Selection mode | browse | Pending / prerequisite-specific |
| playlists.delete_open | Tap Remove selected | Show playlist-deletion confirmation | Selection exists | browse | Pending / prerequisite-specific |
| playlists.delete_confirm | Confirm deletion | Delete selected local/server playlists | Disposable playlist | mutation | Pending / prerequisite-specific |
| playlists.delete_cancel | Cancel deletion | Keep playlists | Confirmation open | browse | Pending / prerequisite-specific |
| playlists.cancel_selection | Tap Cancel | Exit playlist selection | Selection mode | browse | Pending / prerequisite-specific |
| playlist.back | Tap Back to playlists | Return to playlist list | Playlist detail | browse | playlists.detail_navigation |
| playlist.scroll | Scroll tracks | Reveal further playlist tracks | Populated playlist | browse | Pending / prerequisite-specific |
| playlist.play | Tap Play playlist | Play from first track | Populated playlist | playback | Pending / prerequisite-specific |
| playlist.edit_details | Tap Edit details | Open existing playlist editor | Playlist detail | browse | playlists.detail_navigation |
| playlist.edit_tracks | Tap Edit tracks | Enter removable-download selection | Downloaded playlist tracks | browse | Pending / prerequisite-specific |
| playlist.download_open | Tap Download playlist | Show download destination/confirmation | Server playlist | browse | Pending / prerequisite-specific |
| playlist.download_confirm | Confirm download | Queue playlist downloads | Server playlist | mutation | Pending / prerequisite-specific |
| playlist.remove_tracks | Remove selected downloads | Confirm removal of downloaded tracks | Selected downloaded tracks | mutation | Pending / prerequisite-specific |
| playlist_editor.name | Enter playlist name | Update unsaved name and enforce length limit | Editor open | browse | playlists.create_cancel |
| playlist_editor.description | Enter description | Update unsaved description and enforce length limit | Editor open | browse | playlists.create_cancel |
| playlist_editor.target | Select Local or Server | Change new playlist destination | Signed in editor | browse | Pending / prerequisite-specific |
| playlist_editor.image | Tap Choose image | Open native image/file picker | Editor open | native | Pending / prerequisite-specific |
| playlist_editor.save | Tap Save or submit name | Create/update playlist and dismiss on success | Valid draft | mutation | Pending / prerequisite-specific |
| playlist_editor.close | Tap Close or dismiss draft | Discard unsaved draft | Editor open | browse | playlists.create_cancel, playlists.detail_navigation |

## Settings

Sources: [lib/pages/settings_page.dart](../../lib/pages/settings_page.dart), [lib/pages/custom_shuffle_settings_page.dart](../../lib/pages/custom_shuffle_settings_page.dart), [lib/pages/logs_page.dart](../../lib/pages/logs_page.dart), [lib/widgets/display/message_log.dart](../../lib/widgets/display/message_log.dart)

| ID | Visible action | Expected outcome | Available when | Effect | Device journey |
| --- | --- | --- | --- | --- | --- |
| settings.scroll | Scroll settings groups | Reach all General/User/Local Storage/Miscellaneous controls | all | browse | settings.scroll |
| settings.server_actions | Open Server actions | Show connection-dependent server actions | Compact layout | browse | settings.server_menu |
| settings.retry | Tap Retry/reconnect | Attempt server reconnection | Disconnected saved session | network | Pending / prerequisite-specific |
| settings.change_server | Tap Connect/Change server | Open connection flow; may clear current session | Connection-dependent | mutation | settings.server_menu |
| settings.disconnect | Tap Disconnect | Sign out and update UI | Signed-in session | mutation | Pending / prerequisite-specific |
| settings.custom_shuffle | Tap Custom Shuffle | Open shuffle settings | all | browse | settings.custom_shuffle_browse, settings.custom_shuffle_scopes |
| settings.statistics_toggle | Toggle Collect listening statistics | Persist preference and update Stats visibility | all | preference | settings.statistics_controls |
| settings.statistics_reset_open | Tap reset listening statistics | Show account/local reset confirmation | Statistics enabled | browse | settings.statistics_controls |
| settings.statistics_reset_confirm | Confirm statistics reset | Clear selected listening history | Disposable history | mutation | Pending / prerequisite-specific |
| settings.statistics_reset_cancel | Cancel statistics reset | Retain listening history | Confirmation open | browse | settings.statistics_controls |
| settings.password_open | Tap Reset user password | Open password page | Signed-in session | browse | settings.password_browse |
| settings.storage_actions | Open storage row actions | Show available Change/Reset path/Open folder | Platform-dependent controls | browse | Pending / prerequisite-specific |
| settings.storage_change | Tap Change on metadata/audio/logs row | Open path editor or native folder selection | Writable/custom paths | native | Pending / prerequisite-specific |
| settings.storage_path | Edit Folder path | Update draft folder path | Path editor open | browse | Pending / prerequisite-specific |
| settings.storage_save | Save folder path | Move/switch the selected storage category | Valid path | mutation | Pending / prerequisite-specific |
| settings.storage_close | Close path editor | Keep current path | Path editor open | browse | Pending / prerequisite-specific |
| settings.storage_reset | Tap Reset path | Restore category's default storage location | Custom path | mutation | Pending / prerequisite-specific |
| settings.storage_open | Tap Open folder | Open platform file manager | Desktop only | native | Pending / prerequisite-specific |
| settings.reset_open | Tap Full reset | Show Reset local data confirmation | all | browse | settings.reset_cancel |
| settings.reset_confirm | Confirm Reset local data | Clear local downloads/cache/history/session state as implemented | Disposable app data | mutation | Pending / prerequisite-specific |
| settings.reset_cancel | Cancel full reset | Retain local data | Confirmation open | browse | settings.reset_cancel |
| settings.logs | Tap Logs | Open log viewer | all | browse | settings.logs_filters |
| custom_shuffle.target | Select Server or Local | Choose settings scope | Server available for server tab | browse | settings.custom_shuffle_scopes |
| custom_shuffle.artists_view | Select Artists tab | Show artist selection/search | Compact layout | browse | settings.custom_shuffle_browse |
| custom_shuffle.genres_view | Select Genres tab | Show genre selection/search | Compact layout | browse | settings.custom_shuffle_browse |
| custom_shuffle.search | Type/clear artist or genre query | Filter available options without modifying selections | all | browse | settings.custom_shuffle_browse |
| custom_shuffle.scroll | Scroll available artists/genres | Reveal more choices | Enough options | browse | Pending / prerequisite-specific |
| custom_shuffle.artist_toggle | Tap artist checkbox | Persist chosen artists | Artist available | preference | Pending / prerequisite-specific |
| custom_shuffle.genre_toggle | Tap genre checkbox | Persist chosen genres | Genre available | preference | Pending / prerequisite-specific |
| custom_shuffle.select_all | Tap Select all in current section | Persist all choices | Options available | preference | Pending / prerequisite-specific |
| custom_shuffle.clear | Tap Clear in current section | Clear persisted selection | Selection exists | preference | Pending / prerequisite-specific |
| custom_shuffle.back | Tap Back to settings | Return to Settings | all | browse | settings.custom_shuffle_browse |
| logs.filter_all | Tap All | Show combined log history | all | browse | settings.logs_filters |
| logs.filter_info | Tap Info | Show informational entries | all | browse | settings.logs_filters |
| logs.filter_activities | Tap Activities | Show status/activity entries | all | browse | settings.logs_filters |
| logs.filter_warnings | Tap Warnings | Show warning entries | all | browse | settings.logs_filters |
| logs.filter_errors | Tap Errors | Show error entries | all | browse | settings.logs_filters |
| logs.filter_issues | Tap Issues | Show warnings and errors | all | browse | settings.logs_filters |
| logs.filter_debug | Tap Debug | Show debug entries | all | browse | settings.logs_filters |
| logs.scroll | Scroll log entries | Reveal older/newer retained entries | Enough log entries | browse | Pending / prerequisite-specific |
| logs.copy | Tap Copy All | Copy current filtered history to clipboard | all | clipboard | Pending / prerequisite-specific |
| logs.clear | Tap Clear | Delete persisted log history | all | mutation | Pending / prerequisite-specific |
| logs.select_text | Long-press/select log text | Expose supported selection/copy actions | Platform text selection | browse | Pending / prerequisite-specific |
| logs.back | Tap Back to settings | Return to Settings | all | browse | settings.logs_filters |

## Shared Platform

Sources: [lib/widgets/ui/compact_hero_details.dart](../../lib/widgets/ui/compact_hero_details.dart), [lib/widgets/ui/dismissible_selection_area.dart](../../lib/widgets/ui/dismissible_selection_area.dart), [lib/widgets/navigation/desktop_mouse_navigation.dart](../../lib/widgets/navigation/desktop_mouse_navigation.dart), [lib/widgets/navigation/desktop_playback_shortcuts.dart](../../lib/widgets/navigation/desktop_playback_shortcuts.dart), [lib/pages/search_page.dart](../../lib/pages/search_page.dart), [lib/pages/splash_page.dart](../../lib/pages/splash_page.dart)

| ID | Visible action | Expected outcome | Available when | Effect | Device journey |
| --- | --- | --- | --- | --- | --- |
| shared.modal_dismiss | Tap dismissible modal barrier or Close/Cancel | Return without committing a choice | Dismissible overlay | browse | Pending / prerequisite-specific |
| shared.modal_scroll | Scroll long modal contents | Reveal additional controls | Overflowing modal | browse | Pending / prerequisite-specific |
| shared.text_selection | Long-press selectable metadata/text | Expose platform text-selection controls | Selectable text | browse | Pending / prerequisite-specific |
| shared.keyboard_next | Use keyboard Next/Done/Search | Move focus or invoke documented field action | Focused input | browse | Pending / prerequisite-specific |
| shared.disabled | Tap disabled/loading controls | No action is performed | Disabled state | browse | Pending / prerequisite-specific |
| shared.drawer_back | Use visible back link from nested route | Return to correct originating screen | Nested route | browse | Pending / prerequisite-specific |
| native.image_picker | Use iOS image picker and cancel/confirm | Return image selection to playlist editor | Requires native automation | native | Pending / prerequisite-specific |
| native.permission_dialog | Respond to local-network/OS permission prompt | Allow or deny access and return to app | Requires native automation | native | Pending / prerequisite-specific |
| native.output_route | Use system audio routing UI | Switch actual audio output | Requires native automation | native | Pending / prerequisite-specific |
| desktop.mouse_history | Use mouse Back/Forward | Navigate current tab history | Desktop only | browse | Pending / prerequisite-specific |
| desktop.space | Press Space outside inputs | Toggle playback once per keypress | Desktop only | playback | Pending / prerequisite-specific |
| desktop.volume | Adjust visible desktop volume control | Update volume | Desktop layout | preference | Pending / prerequisite-specific |
| unreachable.search_page | Standalone SearchPage filter chips/search/results | Not reachable from current HomePage navigation; do not count as shipped coverage | Source-only page | browse | Pending / prerequisite-specific |
| unreachable.splash_page | Standalone SplashPage controls | Not mounted by current main/HomePage; excluded from reachable coverage | Source-only page | browse | Pending / prerequisite-specific |

## Stats

Sources: [lib/pages/stats_page.dart](../../lib/pages/stats_page.dart), [lib/widgets/display/stats_cards.dart](../../lib/widgets/display/stats_cards.dart)

| ID | Visible action | Expected outcome | Available when | Effect | Device journey |
| --- | --- | --- | --- | --- | --- |
| stats.scroll | Scroll charts and rankings | Reveal lower ranking sections | Statistics enabled | browse | stats.scroll |
| stats.previous_month | Tap previous month | Load preceding month/all-month selection | Statistics enabled | network | Pending / prerequisite-specific |
| stats.next_month | Tap next month | Load following month/all-month selection | Statistics enabled | network | Pending / prerequisite-specific |
| stats.previous_year | Tap previous year | Load preceding year | Statistics enabled | network | Pending / prerequisite-specific |
| stats.next_year | Tap next year | Load following year | Statistics enabled | network | Pending / prerequisite-specific |
| stats.refresh | Tap Refresh listening history | Reload current period | Statistics enabled | network | Pending / prerequisite-specific |
| stats.status_open | Tap Listening history status | Open synchronization/collection details | Statistics enabled | browse | stats.status |
| stats.status_close | Tap Close | Return to statistics | Status dialog | browse | stats.status |
| stats.import_open | Tap Add local history | Open import confirmation | Eligible local history and signed-in session | browse | Pending / prerequisite-specific |
| stats.import_confirm | Confirm Add history | Merge device listening history into account | Disposable history | mutation | Pending / prerequisite-specific |
| stats.import_cancel | Cancel import | Retain separate local/account history | Confirmation open | browse | Pending / prerequisite-specific |
| stats.artist_open | Tap ranked artist | Open artist details | Ranked artist resolvable | browse | Pending / prerequisite-specific |
| stats.track_open | Tap ranked track | Open corresponding detail/playback path | Ranked track resolvable | browse | Pending / prerequisite-specific |

## Tracks

Sources: [lib/widgets/display/track_row_tile.dart](../../lib/widgets/display/track_row_tile.dart), [lib/widgets/display/track_sliver_list.dart](../../lib/widgets/display/track_sliver_list.dart), [lib/widgets/display/search_result_tile.dart](../../lib/widgets/display/search_result_tile.dart), [lib/widgets/modals/add_to_playlist_modal.dart](../../lib/widgets/modals/add_to_playlist_modal.dart)

| ID | Visible action | Expected outcome | Available when | Effect | Device journey |
| --- | --- | --- | --- | --- | --- |
| track.play | Tap an enabled track row | Start selected track using its source queue | Playable track | playback | Pending / prerequisite-specific |
| track.long_press | Long-press an eligible downloaded track | Enter selection with that track selected | Downloaded track | browse | Pending / prerequisite-specific |
| track.actions_open | Tap Track actions | Open actions modal/menu | Track exists | browse | Pending / prerequisite-specific |
| track.like | Tap Like or Unlike | Update appropriate local/server liked state | Track exists | mutation | Pending / prerequisite-specific |
| track.add_open | Tap Add to playlist | Open scoped playlist chooser | Track exists | browse | Pending / prerequisite-specific |
| track.delete_open | Tap Delete | Open removal confirmation | Reusable callback only; no current page supplies onTrackDelete/onDelete | browse | Pending / prerequisite-specific |
| track.actions_close | Close actions or tap dismissible barrier | Return without applying an action | Actions open | browse | Pending / prerequisite-specific |
| add_to_playlist.search | Type/clear playlist filter | Filter chooser's playlist list | Chooser open | browse | Pending / prerequisite-specific |
| add_to_playlist.add | Tap eligible playlist/add control | Add song to chosen playlist | Eligible playlist | mutation | Pending / prerequisite-specific |
| add_to_playlist.remove_open | Tap Remove from playlist | Open removal confirmation | Song already in playlist | browse | Pending / prerequisite-specific |
| add_to_playlist.remove_confirm | Confirm song removal | Remove song from that playlist | Confirmation open | mutation | Pending / prerequisite-specific |
| add_to_playlist.remove_cancel | Cancel song removal | Retain membership | Confirmation open | browse | Pending / prerequisite-specific |
| add_to_playlist.close | Tap Close or dismiss chooser | Return to prior screen | Chooser open | browse | Pending / prerequisite-specific |
| track.download | Tap Download in track actions | Queue a local download | Server track | mutation | Pending / prerequisite-specific |
| track.remove_download | Tap Remove download in track actions | Open local download-removal confirmation | Reusable callback only; no current page supplies onTrackRemoveDownload/onRemoveDownload | browse | Pending / prerequisite-specific |

