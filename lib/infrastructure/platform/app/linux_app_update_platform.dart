import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:phonolite_app/data/models/updates/app_update_configuration.dart';
import 'package:phonolite_app/data/models/updates/app_update_progress.dart';
import 'package:phonolite_app/data/models/updates/app_update_release.dart';
import 'package:phonolite_app/data/models/updates/linux_update_asset.dart';
import 'package:phonolite_app/infrastructure/platform/app/app_update_platform.dart';
import 'package:phonolite_app/infrastructure/platform/app/app_update_preparation_platform.dart';
import 'package:phonolite_app/infrastructure/platform/app/app_update_progress_source.dart';
import 'package:phonolite_app/infrastructure/updates/app_update_feed.dart';
import 'package:phonolite_app/infrastructure/updates/linux_update_process.dart';
import 'package:phonolite_app/infrastructure/updates/app_update_transport.dart';

class LinuxAppUpdatePlatform
    implements AppUpdatePlatform, AppUpdateFeed, AppUpdateProgressSource, AppUpdatePreparationPlatform {
  final LinuxUpdateProcess _process;
  final AppUpdateTransport _transport;
  final ValueNotifier<AppUpdateProgress> _progress = ValueNotifier(const AppUpdateProgress());
  AppUpdateConfiguration? _configuration;
  Future<void> Function()? _onInstall;
  Future<void> Function()? _prepare;
  Directory? _stage;
  LinuxUpdateAsset? _asset;
  String? _signatureUrl;
  bool _handedOff = false;
  bool _closed = false;
  int _generation = 0;

  LinuxAppUpdatePlatform({this._process = const LinuxUpdateProcess(), AppUpdateTransport? transport})
    : _transport = transport ?? AppUpdateTransport();

  @override
  ValueListenable<AppUpdateProgress> get progress => _progress;

  @override
  void setPreparationCallback(Future<void> Function() prepare) => _prepare = prepare;

  @override
  Future<AppUpdateConfiguration> initialize({required Future<void> Function() onInstall}) async {
    _onInstall = onInstall;
    _closed = false;
    Map<String, dynamic> description;
    try {
      description = (await _process.command(['--describe'])) as Map<String, dynamic>;
    } on ProcessException {
      return const AppUpdateConfiguration(
        available: false,
        feedUrl: '',
        currentVersion: '',
        disabledReason: 'Automatic Linux updates require an installed Phonolite release package.',
      );
    }

    _signatureUrl = description['signatureUrl'] as String?;
    _configuration = AppUpdateConfiguration.fromPlatform(description);
    final session = description['sessionResult'] as Map<String, dynamic>?;
    if (session != null &&
        session['package_version'] == _configuration!.currentVersion &&
        {'relaunch-requested', 'relaunch-failed'}.contains(session['state'])) {
      await _process.command(['--acknowledge-relaunch', session['correlation'] as String]);
    }

    final receipt = description['receipt'] as Map<String, dynamic>?;
    if (receipt != null && receipt['state'] != 'succeeded') {
      _setProgress(
        AppUpdatePhase.recoveryRequired,
        message:
            'A previous update did not finish successfully. Check your native package manager before retrying. '
            'After repair, select to check again; user data is retained.',
      );
    }

    return _configuration!;
  }

  @override
  void close() {
    _closed = true;
    ++_generation;
    _transport.cancel();
  }

  @override
  Future<void> dispose() async {
    close();
    if (!_handedOff) {
      await _removeStage();
    }

    _onInstall = null;
    _prepare = null;
  }

  @override
  Future<AppUpdateRelease?> latest(AppUpdateConfiguration configuration) async {
    if (_handedOff) {
      throw StateError('An update is already being installed.');
    }

    final generation = ++_generation;
    _setProgress(AppUpdatePhase.idle);
    await _removeStage();
    final stage = await _process.createPrivateStage();
    if (_closed || generation != _generation) {
      await stage.delete(recursive: true);

      return null;
    }

    _stage = stage;
    try {
      final manifest = await _transport.metadata(Uri.parse(configuration.feedUrl));
      final signature = await _transport.metadata(Uri.parse(_signatureUrl!), maximum: 8192);
      await _process.writePrivateFile(File('${stage.path}/manifest.json'), manifest);
      await _process.writePrivateFile(File('${stage.path}/manifest.sig'), signature);
      final selected = await _process.command([
        '--select',
        '${stage.path}/manifest.json',
        '${stage.path}/manifest.sig',
      ]);
      if (_closed || generation != _generation) {
        if (await stage.exists()) {
          await stage.delete(recursive: true);
        }

        if (identical(_stage, stage)) {
          _stage = null;
        }

        return null;
      }

      if (selected == null) {
        _asset = null;
        await _removeStage();

        return null;
      }

      _asset = LinuxUpdateAsset.fromVerifiedJson(selected as Map<String, dynamic>);

      return AppUpdateRelease(version: _asset!.version);
    } on Object catch (_) {
      if (generation == _generation) {
        _asset = null;
        await _removeStage();
      }

      rethrow;
    }
  }

  @override
  Future<void> showUpdate() async {
    if (_stage == null && !_closed && !_handedOff && _configuration != null) {
      await latest(_configuration!);
    }

    final stage = _stage;
    final asset = _asset;
    if (stage == null || asset == null || _handedOff || _closed || _prepare == null) {
      throw StateError('Check for updates again before installing.');
    }

    final generation = _generation;
    var preparationFailed = false;
    final candidate = File('${stage.path}/candidate');
    try {
      await _process.writePrivateFile(candidate, const []);
      _setProgress(AppUpdatePhase.downloading, fraction: 0);
      await _transport.download(
        asset.url,
        candidate,
        length: asset.length,
        digest: asset.sha256,
        onProgress: (fraction) {
          if (!_closed && generation == _generation) {
            _setProgress(AppUpdatePhase.downloading, fraction: fraction);
          }
        },
      );
      if (_closed || generation != _generation) {
        throw const UpdateDownloadCancelled();
      }

      _setProgress(AppUpdatePhase.verifying);
      if (asset.format == 'archlinux') {
        final proof = await _transport.metadata(Uri.parse('${asset.url}.sig'), maximum: 65536);
        await _process.writePrivateFile(File('${stage.path}/candidate.sig'), proof);
      }

      // The helper rechecks the installed descriptor and signed manifest before
      // accepting the request; the root installer repeats those checks on copies.
      await _process.command(['--select', '${stage.path}/manifest.json', '${stage.path}/manifest.sig']);
      if (_closed || generation != _generation) {
        throw const UpdateDownloadCancelled();
      }

      final identity = await _process.applicationIdentity();
      final random = Random.secure();
      final correlation = List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await _process.writePrivateFile(
        File('${stage.path}/request.json'),
        utf8.encode(
          jsonEncode({
            'schema': 1,
            'correlation': correlation,
            'pid': identity.pid,
            'start': identity.startTime,
            'expected_version': _configuration!.currentVersion,
          }),
        ),
      );
      if (_closed || generation != _generation) {
        throw const UpdateDownloadCancelled();
      }

      _setProgress(AppUpdatePhase.authorizing);
      final coordinator = await _process.coordinate(stage.path);
      // Once spawned the coordinator is independent; disposal must leave its
      // files and process alive, including after Flutter's normal cleanup.
      _handedOff = true;
      unawaited(coordinator.stderr.drain<void>());
      await for (final line in coordinator.stdout.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.length > 65536) {
          throw const FormatException('Invalid coordinator response.');
        }

        final event = jsonDecode(line) as Map<String, dynamic>;
        switch (event['event']) {
          case 'ready':
            if (event['correlation'] != correlation) {
              throw const FormatException('Mismatched update response.');
            }

            _setProgress(AppUpdatePhase.preparing);
            try {
              preparationFailed = true;
              await _prepare!();
              coordinator.stdin.writeln('prepared');
              await coordinator.stdin.flush();
              _setProgress(AppUpdatePhase.installing);
              await _onInstall!();
              preparationFailed = false;
            } on Object catch (_) {
              coordinator.stdin.writeln('abort');
              await coordinator.stdin.flush();
              rethrow;
            }
          case 'failed':
            throw StateError(event['message'] as String? ?? 'The Linux installer stopped.');
          default:
            throw const FormatException('Unknown coordinator response.');
        }
      }

      throw StateError(
        'The update coordinator closed before application exit. Check the updater window for recovery details.',
      );
    } on UpdateDownloadCancelled {
      _setProgress(AppUpdatePhase.idle, message: 'Download cancelled. Select to try again.');
    } on Object catch (error) {
      _setProgress(
        preparationFailed ? AppUpdatePhase.restartRequired : AppUpdatePhase.failed,
        message: preparationFailed ? 'Restart Phonolite before trying the update again. $error' : error.toString(),
      );
      rethrow;
    } finally {
      // A failed/cancelled coordinator keeps its own window until dismissed.
      // It owns its request files after handoff. A new attempt gets a new stage.
      if (_handedOff) {
        _stage = null;
        _asset = null;
      }

      _handedOff = false;
    }
  }

  @override
  void cancelDownload() {
    if (!_progress.value.cancellable) {
      return;
    }

    ++_generation;
    _transport.cancel();
  }

  void _setProgress(AppUpdatePhase phase, {double? fraction, String? message}) {
    if (!_closed) {
      _progress.value = AppUpdateProgress(phase: phase, fraction: fraction, message: message);
    }
  }

  Future<void> _removeStage() async {
    final stage = _stage;
    _stage = null;
    if (stage != null && await stage.exists()) {
      await stage.delete(recursive: true);
    }
  }
}
