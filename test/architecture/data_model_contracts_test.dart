import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/models/audio/stream_settings.dart';
import 'package:phonolite_app/data/models/auth/auth_state.dart';
import 'package:phonolite_app/data/models/library/artist_credit.dart';
import 'package:phonolite_app/data/models/library/track.dart';
import 'package:phonolite_app/data/models/listening_stats/listening_artist.dart';
import 'package:phonolite_app/data/models/playback/playback_state.dart';
import 'package:phonolite_app/data/models/preferences/log_storage_location.dart';
import 'package:phonolite_app/data/rules/listening_stats/listening_primary_artist.dart';

void main() {
  group('nullable copy contracts', () {
    test('auth errors distinguish omission, clearing and replacement', () {
      final original = AuthState(
        baseUrl: 'https://server.test',
        status: SessionStatus.serverUnavailable,
        error: 'Connection lost',
        isReconnecting: true,
      );

      final retained = original.copyWith();
      expect(retained.error, 'Connection lost');
      expect(retained.isReconnecting, isTrue);
      expect(original.copyWith(error: null).error, isNull);
      expect(original.copyWith(error: 'Retry failed').error, 'Retry failed');
      expect(original.error, 'Connection lost');
      expect(() => original.copyWith(error: 1), throwsA(isA<TypeError>()));
    });

    test('playback nullable state is retained unless explicitly changed', () {
      final original = _playbackState();
      final retained = original.copyWith(isPlaying: false);
      expect(retained.track, same(original.track));
      expect(retained.bitrateKbps, 128);
      expect(retained.streamRttMs, 20);
      expect(retained.queueSourcePlaylistId, 'playlist');
      expect(retained.isPlaying, isFalse);

      final cleared = original.copyWith(
        track: null,
        bitrateKbps: null,
        streamRttMs: null,
        queueSourcePlaylistId: null,
      );
      expect(cleared.track, isNull);
      expect(cleared.bitrateKbps, isNull);
      expect(cleared.streamRttMs, isNull);
      expect(cleared.queueSourcePlaylistId, isNull);

      final replacementTrack = original.track!.copyWith(title: 'Updated');
      final replaced = original.copyWith(
        track: replacementTrack,
        bitrateKbps: 256,
        streamRttMs: 10,
        queueSourcePlaylistId: 'next-playlist',
      );
      expect(replaced.track, same(replacementTrack));
      expect(replaced.bitrateKbps, 256.0);
      expect(replaced.streamRttMs, 10);
      expect(replaced.queueSourcePlaylistId, 'next-playlist');
      expect(original.bitrateKbps, 128);
      expect(original.streamRttMs, 20);
    });
  });

  group('value contracts', () {
    test(
      'primary listening artists preserve attribution and value identity',
      () {
        final primary = listeningPrimaryArtist({
          'artist_id': 'main',
          'artist_name': 'Main & Guest',
          'artists': [
            {'id': 'guest', 'name': 'Guest'},
            {'id': 'main', 'name': 'Main'},
          ],
        });
        expect(primary, const ListeningArtist(id: 'main', name: 'Main'));
        final decoded = ListeningArtist.fromJson(primary!.toJson());
        expect(identical(primary, decoded), isFalse);
        expect({primary: 'attribution'}[decoded], 'attribution');
        expect(
          primary,
          isNot(const ListeningArtist(id: 'other', name: 'Main')),
        );
        expect(
          primary,
          isNot(const ListeningArtist(id: 'main', name: 'Other')),
        );
      },
    );

    test('primary listening artist fallbacks retain their previous values', () {
      expect(
        listeningPrimaryArtist({'artist_id': 'main'}),
        const ListeningArtist(id: 'main', name: 'main'),
      );
      expect(
        listeningPrimaryArtist({'artist_name': ' Main '}),
        const ListeningArtist(id: '', name: 'Main'),
      );
      expect(
        listeningPrimaryArtist({
          'artists': [
            {'id': '', 'name': ''},
            {'id': 'guest', 'name': ''},
          ],
        }),
        const ListeningArtist(id: 'guest', name: 'guest'),
      );
      expect(listeningPrimaryArtist({}), isNull);
    });

    test(
      'stream settings compare all encoding choices and hash consistently',
      () {
        final original = StreamSettings(mode: 'fixed', quality: 'high');
        final equal = StreamSettings(mode: 'fixed', quality: 'high');
        expect(identical(original, equal), isFalse);
        expect(original, equal);
        expect({original: 'stream'}[equal], 'stream');
        expect(
          original,
          isNot(const StreamSettings(mode: 'auto', quality: 'high')),
        );
        expect(
          original,
          isNot(const StreamSettings(mode: 'fixed', quality: 'low')),
        );
        expect(
          original,
          isNot(
            const StreamSettings(mode: 'fixed', quality: 'high', frameMs: 40),
          ),
        );
      },
    );

    test('artist credits compare every persisted credit field', () {
      final original = ArtistCredit(
        artistId: 'artist',
        name: 'Artist',
        creditedName: 'Alias',
        role: 'featured',
        joinPhrase: ' & ',
      );
      final equal = ArtistCredit.fromJson(original.toJson());
      expect(original, equal);
      expect({original: 'credit'}[equal], 'credit');
      for (final key in original.toJson().keys) {
        final changed = ArtistCredit.fromJson({
          ...original.toJson(),
          key: 'changed',
        });
        expect(original, isNot(changed), reason: '$key defines the credit');
      }
    });

    test('log locations compare their directory and default-location flag', () {
      final original = LogStorageLocation(directory: 'logs', isDefault: true);
      final equal = LogStorageLocation(directory: 'logs', isDefault: true);
      expect(original, equal);
      expect({original: 'location'}[equal], 'location');
      expect(
        original,
        isNot(const LogStorageLocation(directory: 'other', isDefault: true)),
      );
      expect(
        original,
        isNot(const LogStorageLocation(directory: 'logs', isDefault: false)),
      );
    });

    test('entities retain instance identity despite equal metadata', () {
      final original = _playbackState().track!;
      final copy = original.copyWith();
      expect(original, isNot(copy));
      expect(original.toJson(), copy.toJson());
    });
  });
}

PlaybackState _playbackState() => PlaybackState(
  track: Track.fromJson({
    'id': 'track',
    'title': 'Track',
    'duration_ms': 60000,
  }),
  isPlaying: true,
  isLoading: false,
  position: const Duration(seconds: 1),
  duration: const Duration(minutes: 1),
  bufferRatio: 1,
  volume: 0.5,
  shuffleMode: ShuffleMode.off,
  shuffleScope: ActionScope.local,
  repeatMode: RepeatMode.off,
  streamMode: StreamMode.auto,
  bitrateKbps: 128,
  streamConnected: true,
  streamRttMs: 20,
  queueSource: PlaybackQueueSource.playlist,
  queueSourcePlaylistId: 'playlist',
  localPlaybackSource: LocalPlaybackSource.none,
  isLocalPlayback: false,
);
