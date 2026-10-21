import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_test_helpers.dart';

const _root = 'android/app/src/main/kotlin/com/example/phonolite_app/';

void main() {
  test('Android native source packages match physical responsibility owners', () {
    const areas = {'bootstrap', 'data', 'application', 'infrastructure', 'ui'};

    for (final file in Directory(_root).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.kt')) continue;

      final path = file.path.replaceAll('\\', '/');
      final relative = path.substring(_root.length);
      final source = file.readAsStringSync();
      final segments = relative.split('/');
      final package = 'com.example.phonolite_app.${segments.take(segments.length - 1).join('.')}';

      expect(areas, contains(segments.first), reason: path);
      expect(source, startsWith('package $package'), reason: path);
      expect(segments.last, matches(r'^[A-Z][A-Za-z0-9]*\.kt$'), reason: path);
      expect(file.readAsLinesSync().length, lessThanOrEqualTo(1000), reason: path);

      if (relative.startsWith('data/') || relative.startsWith('application/')) {
        expect(
          source,
          isNot(matches(RegExp(r'^import (?:android\.|androidx\.|io\.flutter\.)', multiLine: true))),
          reason: path,
        );
      }

      if (!relative.startsWith('bootstrap/')) {
        expect(source, isNot(contains('import com.example.phonolite_app.bootstrap.')), reason: path);
      }

      if (relative.startsWith('infrastructure/')) {
        expect(source, isNot(contains('import com.example.phonolite_app.ui.')), reason: path);
      }

      if (relative.startsWith('infrastructure/audio/')) {
        expect(source, isNot(contains('MethodChannel')), reason: path);
        expect(source, isNot(contains('MethodCall')), reason: path);
      }
    }
  });

  test('Android service and Activity share one completely initialized engine binding', () {
    final engine = _native('bootstrap/FlutterEngineOwner.kt');
    final startup = [
      'FlutterEngine(appContext, null, false)',
      'GeneratedPluginRegister.registerGeneratedPlugins(engine)',
      'createBinding(engine.dartExecutor.binaryMessenger)',
      'binding.attach()',
      'executeDartEntrypoint(',
      'session = created',
    ].map(engine.indexOf).toList();

    expect(startup, everyElement(greaterThanOrEqualTo(0)));
    expect(startup, orderedEquals([...startup]..sort()));
    expect(_native('bootstrap/MainActivity.kt'), contains('shouldDestroyEngineWithHost(): Boolean = false'));

    final service = _native('bootstrap/PhonoliteMediaService.kt');
    expect(service.indexOf('host.getOrCreateEngine()'), lessThan(service.indexOf('assembleMediaOwners()')));
    expect(
      service.indexOf('host.mediaServiceGateway.detach(this)'),
      lessThan(service.indexOf('mediaSession.release()')),
    );
    expect(service, contains('return START_STICKY'));
  });

  test('Android transport shares handler lifecycle and keeps wire identities', () {
    final adapter = _native('infrastructure/flutter/FlutterChannelAdapter.kt');
    expectContainsAll(adapter, const [
      'fun attach()',
      'fun detach()',
      'endpoint.setHandler(null)',
      'dispatchToPlatform',
    ]);

    for (final name in ['NowPlayingChannelAdapter', 'VehicleChannelAdapter', 'AudioOutputChannelAdapter']) {
      expect(_native('infrastructure/flutter/$name.kt'), contains(': FlutterChannelAdapter('));
    }

    final actions = _native('infrastructure/media/MediaServiceActions.kt');
    expectContainsAll(actions, const ['"phonolite.playback"', '3010', '"phonolite_media_session"']);
    final pendingIntents = _native('infrastructure/media/MediaPendingIntents.kt');
    expectContainsAll(pendingIntents, const ['FLAG_UPDATE_CURRENT', 'FLAG_IMMUTABLE']);
  });

  test('Android focus loss permits reacquisition while preserving final registration cleanup', () {
    final focus = _native('infrastructure/audio/AudioFocusController.kt');
    final loss = focus.substring(focus.indexOf('AUDIOFOCUS_LOSS,'), focus.indexOf('AUDIOFOCUS_GAIN ->'));

    expect(loss.indexOf('hasFocus = false'), greaterThanOrEqualTo(0));
    expect(loss.indexOf('hasFocus = false'), lessThan(loss.indexOf('onPauseRequested()')));
    expect(loss, isNot(contains('focusRegistered = false')));
    expect(focus, contains('if (hasFocus)'));

    final abandon = focus.substring(focus.indexOf('fun abandonFocus()'), focus.indexOf('fun registerNoisyReceiver()'));
    expect(abandon, contains('if (!focusRegistered)'));
    expect(abandon.indexOf('abandonAudioFocusRequest('), lessThan(abandon.indexOf('focusRegistered = false')));
    expectContainsAll(abandon, const ['focusRegistered = false', 'hasFocus = false']);
  });
}

String _native(String relativePath) => readProjectFile('$_root$relativePath');
