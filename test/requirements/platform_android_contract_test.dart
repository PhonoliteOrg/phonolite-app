import 'package:flutter_test/flutter_test.dart';

import '../support/source_test_helpers.dart';

void main() {
  group('android platform source contracts', () {
    test(
      'manifest declares expected permissions cleartext and media service',
      () {
        final manifest = readProjectFile(
          'android/app/src/main/AndroidManifest.xml',
        );

        expectContainsAll(manifest, const [
          'android.permission.INTERNET',
          'android.permission.ACCESS_NETWORK_STATE',
          'android.permission.WAKE_LOCK',
          'android.permission.POST_NOTIFICATIONS',
          'android.permission.FOREGROUND_SERVICE',
          'android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK',
          'android:usesCleartextTraffic="true"',
          '.PhonoliteApplication',
          '.PhonoliteMediaService',
          'android.permission.BIND_MEDIA_BROWSER_SERVICE',
          'android.media.browse.MediaBrowserService',
        ]);
      },
    );

    test('build files preserve app identity and automotive media support', () {
      final appBuild = readProjectFile('android/app/build.gradle.kts');
      final automotive = readProjectFile(
        'android/app/src/main/res/xml/automotive_app_desc.xml',
      );

      expectContainsAll(appBuild, const [
        'applicationId = "com.example.phonolite_app"',
        'implementation("androidx.media:media:1.7.0")',
        'rename { "phonolite-release.apk" }',
      ]);
      expectContainsAll(automotive, const ['<uses name="media" />']);
    });

    test(
      'kotlin bridge preserves shared engine media notifications and audio control',
      () {
        final appSource = readProjectFile(
          'android/app/src/main/kotlin/com/example/phonolite_app/PhonoliteApplication.kt',
        );
        final bridgeSource = readProjectFile(
          'android/app/src/main/kotlin/com/example/phonolite_app/PhonolitePlatformBridge.kt',
        );
        final mediaSource = readProjectFile(
          'android/app/src/main/kotlin/com/example/phonolite_app/PhonoliteMediaService.kt',
        );
        final outputSource = readProjectFile(
          'android/app/src/main/kotlin/com/example/phonolite_app/PhonoliteAudioOutputManager.kt',
        );

        expectContainsAll(appSource, const [
          'private var flutterEngine: FlutterEngine? = null',
          'private var platformBridge: PhonolitePlatformBridge? = null',
          'fun getOrCreateFlutterEngine(): FlutterEngine {',
          'executeDartEntrypoint(',
        ]);
        expectContainsAll(bridgeSource, const [
          '"phonolite/now_playing"',
          '"phonolite/carplay"',
          '"phonolite/audio_output"',
          'PhonoliteMediaService.publishNowPlaying(',
          'PhonoliteMediaService.updateAuthorization(',
          'PhonoliteMediaService.updateSourceState(',
          '"carPlayState"',
        ]);
        expectContainsAll(mediaSource, const [
          'serverAvailable',
          'localAvailable',
          'hasAnySource',
          'localArtistsId',
          'localAlbumPrefix',
          'localLikedId',
          'title = "No available library"',
          'mapOf("scope" to "local")',
          '"Home"',
          '"Artists"',
          '"Playlists"',
          '"Liked Songs"',
          '"startLibraryShuffle"',
          '"startLikedShuffle"',
          '"startCustomShuffle"',
          'NotificationCompat.CATEGORY_TRANSPORT',
        ]);
        expectContainsAll(outputSource, const [
          'requestAudioFocus()',
          'ACTION_AUDIO_BECOMING_NOISY',
          'AudioTrack.Builder()',
          'setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)',
          'listOutputDevices(): List<Map<String, Any>>',
          '"System Default"',
        ]);
      },
    );
  });
}
