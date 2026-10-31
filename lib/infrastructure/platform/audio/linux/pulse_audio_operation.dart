import 'dart:ffi';

import 'package:phonolite_app/infrastructure/platform/audio/linux/pulse_audio_bindings.dart';

/// Owns a libpulse acknowledgement and its isolate-local callback together.
class PulseAudioOperation {
  final PulseAudioBindings _api;
  Pointer<Void> _handle = nullptr;
  late final NativeCallable<PulseSuccessCallback> _callback;
  bool _succeeded = false;
  bool _disposed = false;

  PulseAudioOperation(
    this._api, {
    required Pointer<Void> Function(Pointer<NativeFunction<PulseSuccessCallback>> callback) start,
  }) {
    _callback = NativeCallable<PulseSuccessCallback>.isolateLocal(_onComplete);

    try {
      _handle = start(_callback.nativeFunction);
      if (_handle == nullptr) {
        throw StateError('Could not start the Linux audio operation.');
      }
    } catch (_) {
      dispose();
      rethrow;
    }
  }

  /// Null while pending; the server result once the operation has finished.
  bool? poll() {
    final state = _api.operationState(_handle);

    return state == 0 ? null : state == 1 && _succeeded;
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;

    if (_handle != nullptr) {
      _api.operationCancel(_handle);
      _api.operationUnref(_handle);
      _handle = nullptr;
    }
    _callback.close();
  }

  void _onComplete(Pointer<Void> stream, int success, Pointer<Void> userData) {
    _succeeded = success != 0;
  }
}
