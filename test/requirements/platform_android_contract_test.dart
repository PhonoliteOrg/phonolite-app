import 'package:flutter_test/flutter_test.dart';

import '../support/source_test_helpers.dart';

void main() {
  group('android platform source contracts', () {
    test('manifest declares expected permissions cleartext and media service', () {
      final manifest = readProjectFile('android/app/src/main/AndroidManifest.xml');

      expectContainsAll(manifest, const [
        'android.permission.INTERNET',
        'android.permission.ACCESS_NETWORK_STATE',
        'android.permission.WAKE_LOCK',
        'android.permission.POST_NOTIFICATIONS',
        'android.permission.FOREGROUND_SERVICE',
        'android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK',
        'android:usesCleartextTraffic="false"',
        '.bootstrap.PhonoliteApplication',
        '.bootstrap.PhonoliteMediaService',
        'android.media.browse.MediaBrowserService',
        'android:foregroundServiceType="mediaPlayback"',
      ]);
      expect(manifest, isNot(contains('android.permission.BIND_MEDIA_BROWSER_SERVICE')));
    });

    test('build files preserve app identity and automotive media support', () {
      final appBuild = readProjectFile('android/app/build.gradle.kts');
      final automotive = readProjectFile('android/app/src/main/res/xml/automotive_app_desc.xml');

      expectContainsAll(appBuild, const [
        'namespace = "com.phonoliteorg.phonolite_app"',
        'applicationId = "com.phonoliteorg.phonolite_app"',
        'implementation("androidx.media:media:1.7.0")',
        'rename { "phonolite-release.apk" }',
      ]);
      expectContainsAll(automotive, const ['<uses name="media" />']);
    });

    test('native owners preserve shared engine media notifications and audio control', () {
      final engine = _native('bootstrap/FlutterEngineOwner.kt');
      final binding = _native('bootstrap/FlutterEngineBinding.kt');
      final vehicle = _native('infrastructure/flutter/VehicleChannelAdapter.kt');
      final mediaItems = _native('ui/media/MediaItemFactory.kt');
      final mediaIds = _native('data/models/vehicle/VehicleMediaIds.kt');
      final notification = _native('ui/media/PlaybackNotificationFactory.kt');
      final output = _native('infrastructure/audio/AudioOutputSession.kt');
      final focus = _native('infrastructure/audio/AudioFocusController.kt');
      final devices = _native('infrastructure/audio/OutputDeviceCatalog.kt');

      expectContainsAll(engine, const [
        'private var session: EngineSession? = null',
        'fun getOrCreateEngine(): FlutterEngine',
        'executeDartEntrypoint(',
      ]);
      expectContainsAll(binding, const ['"phonolite/now_playing"', '"phonolite/carplay"', '"phonolite/audio_output"']);
      expectContainsAll(vehicle, const ['media.updateAuthorization(', 'media.updateSourceState(', '"carPlayState"']);
      expectContainsAll(mediaIds, const ['"local_artists"', '"local_album:"', '"local_liked"']);
      expectContainsAll(mediaItems, const [
        '"No available library"',
        '"Home"',
        '"Artists"',
        '"Playlists"',
        '"Liked Songs"',
      ]);
      expectContainsAll(vehicle, const ['"startLibraryShuffle"', '"startLikedShuffle"', '"startCustomShuffle"']);
      expect(notification, contains('NotificationCompat.CATEGORY_TRANSPORT'));
      expectContainsAll(output, const [
        'fun flush()',
        'audioTrack.flush()',
        'AudioTrack.Builder()',
        'setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)',
      ]);
      expectContainsAll(focus, const ['fun requestFocus()', 'ACTION_AUDIO_BECOMING_NOISY']);
      expectContainsAll(devices, const ['fun listOutputDevices(): List<OutputDevice>', '"System Default"']);
    });
  });
}

String _native(String relativePath) =>
    readProjectFile('android/app/src/main/kotlin/com/phonoliteorg/phonolite_app/$relativePath');
