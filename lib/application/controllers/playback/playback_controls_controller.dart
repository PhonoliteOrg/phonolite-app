import 'dart:async';
import 'dart:developer' as developer;

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/data/models/library/track.dart';

class PlaybackControlsController {
  static bool canOpenPlaybackDetails(PlaybackState state) {
    final track = state.track;

    return track != null &&
        (state.hasPlaylistSource ||
            state.isLocalPlayback ||
            state.queueSource == PlaybackQueueSource.offline ||
            (track.albumId?.trim().isNotEmpty ?? false));
  }

  static ActionScope actionScopeForPlayback(PlaybackState state) {
    // Shuffle preferences can target a different source than the current song.
    if (state.isLocalPlayback || state.queueSource == PlaybackQueueSource.offline) {
      return ActionScope.local;
    }

    return ActionScope.server;
  }

  static Future<void> toggleLike(AppController controller, PlaybackState playback) {
    final track = playback.track;
    if (track == null) {
      return Future<void>.value();
    }

    if (playback.isLocalPlayback || playback.queueSource == PlaybackQueueSource.offline) {
      return controller.toggleLocalLike(track);
    }

    return controller.toggleLike(track);
  }

  static bool shuffleCanStartWithoutTrack(ShuffleMode mode, ActionScope scope) {
    return switch (mode) {
      ShuffleMode.all || ShuffleMode.custom || ShuffleMode.liked => true,
      ShuffleMode.off || ShuffleMode.artist || ShuffleMode.album || ShuffleMode.currentPlaylist => false,
    };
  }

  static bool localTrackAvailableForShuffle(AppController controller, Track? track) {
    if (track == null) {
      return false;
    }

    for (final offline in controller.offlineTracks) {
      if (offline.id == track.id ||
          offline.localId == track.id ||
          offline.serverTrackId == track.id ||
          (track.localId != null && (offline.id == track.localId || offline.localId == track.localId)) ||
          (track.serverTrackId != null &&
              (offline.id == track.serverTrackId || offline.serverTrackId == track.serverTrackId))) {
        return true;
      }
    }

    return false;
  }

  static void warmShuffleLikedState(
    AppController controller, {
    required bool serverScope,
    required bool serverAvailable,
  }) {
    Future<void>? loadFuture;

    try {
      if (serverScope) {
        if (!serverAvailable || controller.liked.isNotEmpty) {
          return;
        }

        loadFuture = controller.loadLikedTracks();
      } else {
        if (controller.localLiked.isNotEmpty) {
          return;
        }

        loadFuture = controller.loadLocalLikedTracks();
      }
    } catch (err, stack) {
      developer.log('Failed to start shuffle liked-state warmup', name: 'NowPlayingBar', error: err, stackTrace: stack);

      return;
    }

    unawaited(
      loadFuture.catchError((Object err, StackTrace stack) {
        developer.log('Failed to load shuffle liked-state', name: 'NowPlayingBar', error: err, stackTrace: stack);
      }),
    );
  }

  static bool transportControlsEnabled(PlaybackState state) {
    if (state.track != null) {
      return true;
    }

    if (state.shuffleMode == ShuffleMode.currentPlaylist) {
      if (state.shuffleScope == ActionScope.local) {
        return state.queueSource == PlaybackQueueSource.offline && (state.queueSourcePlaylistId?.isNotEmpty ?? false);
      }

      return state.queueSource == PlaybackQueueSource.playlist && (state.queueSourcePlaylistId?.isNotEmpty ?? false);
    }

    return shuffleCanStartWithoutTrack(state.shuffleMode, state.shuffleScope);
  }

  static bool shuffleEnabled(
    AppController controller,
    PlaybackState playback,
    ActionScope scope,
    ShuffleMode mode, {
    required bool likedEnabled,
  }) {
    final serverScope = scope == ActionScope.server;
    final serverAvailable = controller.authState.isAuthorized;
    final settings = controller.customShuffleSettings;
    final customEnabled = serverScope
        ? settings.artistIds.isNotEmpty || settings.genres.isNotEmpty
        : settings.localArtistIds.isNotEmpty || settings.localGenres.isNotEmpty;
    final downloadedEnabled = controller.offlineTracks.isNotEmpty;
    final localContextEnabled = downloadedEnabled && localTrackAvailableForShuffle(controller, playback.track);
    final currentPlaylistEnabled =
        (serverScope
            ? playback.queueSource == PlaybackQueueSource.playlist
            : playback.queueSource == PlaybackQueueSource.offline) &&
        (playback.queueSourcePlaylistId?.isNotEmpty ?? false);

    if (serverScope && !serverAvailable && mode != ShuffleMode.off) {
      return false;
    }

    return switch (mode) {
      ShuffleMode.off => true,
      ShuffleMode.all => serverScope || downloadedEnabled,
      ShuffleMode.artist || ShuffleMode.album => serverScope ? playback.track != null : localContextEnabled,
      ShuffleMode.custom => serverScope ? customEnabled : downloadedEnabled && customEnabled,
      ShuffleMode.liked => likedEnabled,
      ShuffleMode.currentPlaylist => currentPlaylistEnabled,
    };
  }
}
