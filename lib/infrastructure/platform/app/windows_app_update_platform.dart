import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:phonolite_app/data/models/updates/app_update_configuration.dart';
import 'package:phonolite_app/data/models/updates/app_update_progress.dart';
import 'package:phonolite_app/data/models/updates/app_update_release.dart';
import 'package:phonolite_app/data/storage/logs/app_log.dart';
import 'package:phonolite_app/data/storage/updates/windows_update_staging.dart';
import 'package:phonolite_app/infrastructure/platform/app/app_update_platform.dart';
import 'package:phonolite_app/infrastructure/updates/app_update_feed.dart';
import 'package:phonolite_app/infrastructure/updates/app_update_transport.dart';
import 'package:phonolite_app/infrastructure/updates/windows_update_verifier.dart';

class WindowsAppUpdatePlatform
    implements AppUpdatePlatform, AppUpdateFeed, AppUpdateProgressSource, AppUpdatePreparationPlatform {
  final MethodChannel _channel;
  final AppUpdateFeed _feed;
  final AppUpdateTransport _transport;
  final WindowsUpdateVerifier _verifier;
  final WindowsUpdateStaging _staging;
  final ValueNotifier<AppUpdateProgress> _progress = ValueNotifier(const AppUpdateProgress());
  AppUpdateConfiguration? _configuration;
  AppUpdateRelease? _release;
  Future<void> Function()? _onInstall;
  Future<void> Function()? _prepare;
  Future<void>? _operation;
  bool _closed = false;
  bool _handedOff = false;
  int _generation = 0;

  WindowsAppUpdatePlatform({
    this._channel = const MethodChannel('phonolite/updates'),
    AppUpdateFeed? feed,
    AppUpdateTransport? transport,
    this._verifier = const WindowsUpdateVerifier(),
    WindowsUpdateStaging? staging,
  }) : _feed = feed ?? HttpAppUpdateFeed(),
       _transport = transport ?? AppUpdateTransport(),
       _staging = staging ?? WindowsUpdateStaging();

  @override
  ValueListenable<AppUpdateProgress> get progress => _progress;

  @override
  void setPreparationCallback(Future<void> Function() prepare) => _prepare = prepare;

  @override
  Future<AppUpdateConfiguration> initialize({required Future<void> Function() onInstall}) async {
    _closed = false;
    _onInstall = onInstall;
    final values = await _channel.invokeMapMethod<Object?, Object?>('initialize');
    _configuration = AppUpdateConfiguration.fromPlatform(values ?? const {});
    try {
      await _staging.prune();
    } on FileSystemException catch (error) {
      AppLogger.warning('Could not remove old update downloads: $error');
    }
    return _configuration!;
  }

  @override
  void close() {
    _closed = true;
    ++_generation;
    _feed.close();
    _transport.cancel();
  }

  @override
  Future<void> dispose() async {
    close();
    // A normal user quit waits for partial-file cleanup. Once installation is
    // handed off, the independent installer owns its download until restart.
    if (!_handedOff) await _operation;
    _onInstall = null;
    _prepare = null;
    await _channel.invokeMethod<void>('dispose');
  }

  @override
  Future<AppUpdateRelease?> latest(AppUpdateConfiguration configuration) async {
    if (_closed || _operation != null || _handedOff) return null;
    final generation = _generation;
    _release = null;
    _setProgress(AppUpdatePhase.idle);
    final release = await _feed.latest(configuration);
    if (_closed || generation != _generation) return null;
    return _release = release;
  }

  @override
  Future<void> showUpdate() async {
    if (_operation != null) return;
    if (_closed || _handedOff || _release?.windowsAsset == null || _configuration == null || _prepare == null) {
      throw StateError('Check for updates again before installing.');
    }
    final operation = Future<void>.microtask(_downloadAndInstall);
    _operation = operation;
    try {
      await operation;
    } finally {
      _operation = null;
    }
  }

  @override
  void cancelDownload() {
    if (!_progress.value.cancellable) return;
    ++_generation;
    _transport.cancel();
  }

  Future<void> _downloadAndInstall() async {
    final asset = _release!.windowsAsset!;
    final configuration = _configuration!;
    final generation = _generation;
    final prepare = _prepare!;
    final quit = _onInstall!;
    Directory? stage;
    var preparing = false;
    var locked = false;
    try {
      _setProgress(AppUpdatePhase.downloading, fraction: 0);
      stage = await _staging.create();
      _checkActive(generation);
      final candidate = File('${stage.path}/update.exe');
      await _transport.download(
        asset.url,
        candidate,
        length: asset.length,
        onProgress: (fraction) {
          if (!_closed && generation == _generation) _setProgress(AppUpdatePhase.downloading, fraction: fraction);
        },
      );
      _checkActive(generation);
      _setProgress(AppUpdatePhase.verifying);
      _checkActive(generation);
      await _channel.invokeMethod<void>('stageUpdate', {'path': candidate.absolute.path, 'version': _release!.version});
      locked = true;
      await _verifier.verify(candidate, asset, configuration.publicKey);
      _checkActive(generation);

      preparing = true;
      _setProgress(AppUpdatePhase.preparing);
      await prepare();
      _checkActive(generation);
      await _channel.invokeMethod<void>('installUpdate');
      _handedOff = true;
      _setProgress(AppUpdatePhase.installing, message: 'Restarting Phonolite to finish the update…');
      await quit();
    } on UpdateDownloadCancelled {
      _setProgress(AppUpdatePhase.idle, message: 'Download cancelled. Select to try again.');
    } catch (error) {
      _setProgress(
        preparing ? AppUpdatePhase.restartRequired : AppUpdatePhase.failed,
        message: preparing ? 'Restart Phonolite before trying the update again. $error' : error.toString(),
      );
      rethrow;
    } finally {
      if (locked && !_handedOff) {
        try {
          await _channel.invokeMethod<void>('releaseUpdate');
        } on PlatformException catch (error) {
          AppLogger.warning('Could not unlock the update download: $error');
        }
      }
      if (!_handedOff && stage != null) {
        try {
          await stage.delete(recursive: true);
        } on FileSystemException catch (error) {
          AppLogger.warning('Could not remove the incomplete update: $error');
        }
      }
    }
  }

  void _checkActive(int generation) {
    if (_closed || generation != _generation) throw const UpdateDownloadCancelled();
  }

  void _setProgress(AppUpdatePhase phase, {double? fraction, String? message}) {
    if (!_closed) _progress.value = AppUpdateProgress(phase: phase, fraction: fraction, message: message);
  }
}
