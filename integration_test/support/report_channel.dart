import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

/// One acknowledged message at a time. Full traces stay on the host, and the
/// app waits until each journey has been saved before starting the next one.
class UiReportChannel {
  static const extensionName = 'ext.phonolite.uiReport';
  int _sequence = 0;
  Map<String, Object?>? _pending;
  Completer<void>? _acknowledged;
  Completer<void> _available = Completer<void>();

  void register() {
    developer.registerExtension(extensionName, (method, parameters) async {
      final result = await receive(
        acknowledge: int.tryParse(parameters['acknowledge'] ?? ''),
      );
      return developer.ServiceExtensionResponse.result(jsonEncode(result));
    });
  }

  Future<void> publish(Map<String, Object?> event) async {
    if (_pending != null) throw StateError('Previous report is not saved');
    _pending = {'sequence': ++_sequence, 'event': event};
    final saved = _acknowledged = Completer<void>();
    _available.complete();
    _available = Completer<void>();
    await saved.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () => throw TimeoutException('Host did not save UI report'),
    );
  }

  Future<Map<String, Object?>> receive({
    int? acknowledge,
    Duration wait = const Duration(seconds: 5),
  }) async {
    if (_pending != null && acknowledge == _pending!['sequence']) {
      _pending = null;
      _acknowledged!.complete();
      _acknowledged = null;
    }
    if (_pending == null) {
      await _available.future.timeout(wait, onTimeout: () {});
    }
    return _pending ?? const {};
  }
}
