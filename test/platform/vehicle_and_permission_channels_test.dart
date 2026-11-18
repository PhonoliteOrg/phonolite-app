import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/data/models/app/action_scope.dart';
import 'package:phonolite_app/data/models/playback/vehicle_request.dart';
import 'package:phonolite_app/data/models/playback/vehicle_response.dart';
import 'package:phonolite_app/infrastructure/platform/media/vehicle_surface_service.dart';
import 'package:phonolite_app/infrastructure/platform/permissions/local_network_permission_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<Object?> incoming(MethodChannel channel, String method, Map<String, dynamic> arguments) async {
    final response = Completer<ByteData?>();
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
      response.complete,
    );

    return const StandardMethodCodec().decodeEnvelope((await response.future)!);
  }

  group('vehicle surface channel', () {
    const channel = MethodChannel('phonolite/carplay');
    late VehicleSurfaceService service;
    late List<MethodCall> published;

    setUp(() {
      published = [];
      service = VehicleSurfaceService(channel: channel);
      messenger.setMockMethodCallHandler(channel, (call) async {
        published.add(call);

        return null;
      });
    });

    tearDown(() {
      service.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    });

    test('source state and authorization are published to the native vehicle surface', () async {
      await service.notifySourceState(
        const VehicleSourceState(serverAvailable: false, localAvailable: true, playbackScope: ActionScope.local),
      );
      await service.notifyAuthorization(true);

      expect(published.map((call) => call.method), ['carPlayState', 'authState']);
      expect(published.first.arguments, {
        'serverAvailable': false,
        'localAvailable': true,
        'hasAnySource': true,
        'playbackScope': 'local',
      });
      expect(published.last.arguments, {'authorized': true});
    });

    test('a vehicle request is decoded for the handler and its response is returned encoded', () async {
      final requests = <VehicleRequest>[];
      service.setRequestHandler((request) async {
        requests.add(request);

        return const VehicleCommandResult.failure(VehicleFailure.missingAlbum);
      });

      final response = await incoming(channel, 'playAlbum', {'albumId': 'album-7', 'scope': 'local'});

      expect(requests.single.operation, VehicleOperation.playAlbum);
      expect(requests.single.albumId, 'album-7');
      expect(requests.single.scope, ActionScope.local);
      expect(response, {'error': 'missing_album', 'items': <Object?>[]});
    });

    test('a vehicle request the handler does not answer returns no payload', () async {
      service.setRequestHandler((_) async => null);

      expect(await incoming(channel, 'getCarPlayState', {}), isNull);
    });
  });

  group('local network permission channel', () {
    const channel = MethodChannel('phonolite/permissions');
    late LocalNetworkPermissionService service;
    late List<MethodCall> calls;
    Object? permissionResult;

    setUp(() {
      calls = [];
      permissionResult = null;
      service = LocalNetworkPermissionService(channel: channel);
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);

        return call.method == 'getLocalNetworkPermission' ? permissionResult : null;
      });
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      service.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    });

    test('local network permission is only supported on iOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(service.isSupported, isTrue);

      for (final platform in [TargetPlatform.android, TargetPlatform.macOS, TargetPlatform.windows]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(service.isSupported, isFalse, reason: platform.name);
      }
    });

    test('refresh, query and settings requests reach the native permission host', () async {
      permissionResult = '  Granted ';

      await service.refreshPermission();
      final status = await service.getPermission();
      await service.openAppSettings();

      expect(calls.map((call) => call.method), [
        'refreshLocalNetworkPermission',
        'getLocalNetworkPermission',
        'openAppSettings',
      ]);
      expect(status, 'granted');
    });

    test('a missing permission answer reads as an empty status', () async {
      expect(await service.getPermission(), '');
    });

    test('native permission updates are normalized and unrelated calls are ignored', () async {
      final statuses = <String>[];
      service.setStatusHandler(statuses.add);

      await incoming(channel, 'localNetworkPermission', {'status': ' DENIED '});
      await incoming(channel, 'somethingElse', {'status': 'granted'});
      await incoming(channel, 'localNetworkPermission', {});

      expect(statuses, ['denied', '']);
    });
  });
}
