part of 'package:phonolite_app/application/app/app_controller.dart';

class _DiagnosticsCoordinator {
  final AppController _host;
  final _messageController = StreamController<List<LogEntry>>.broadcast();
  final _messages = ListQueue<LogEntry>();
  List<LogEntry>? _messageSnapshot;
  Timer? _messageUpdateTimer;

  _DiagnosticsCoordinator(this._host);

  Stream<List<LogEntry>> get messageStream => _messageController.stream;

  List<LogEntry> get messages => _messageSnapshot ??= List<LogEntry>.unmodifiable(_messages);

  Future<void> clearMessages() {
    _messageUpdateTimer?.cancel();
    _messageUpdateTimer = null;
    _messages.clear();
    _messageSnapshot = null;
    _messageController.add(_host.messages);

    return AppLogger.instance.clear();
  }

  void _pushMessage(String message, {LogLevel level = LogLevel.info}) {
    if (_host._disposed) {
      return;
    }

    AppLogger.instance.log(LogEntry(message: message, level: level));
  }

  void _addLogEntry(LogEntry entry) {
    if (_host._disposed) {
      return;
    }

    _messages.add(entry);

    if (_messages.length > 3000) {
      _messages.removeFirst();
    }

    _messageSnapshot = null;

    if (!_messageController.hasListener) {
      return;
    }

    // Publish at most ten snapshots per second during noisy download/playback
    // bursts, and avoid copying history at all when no UI is observing it.
    void publishMessages() {
      _messageUpdateTimer = null;

      if (!_host._disposed && _messageController.hasListener) {
        _messageController.add(_host.messages);
      }
    }

    _messageUpdateTimer ??= Timer(const Duration(milliseconds: 100), publishMessages);
  }

  String _extractErrorMessage(String body) {
    try {
      final decoded = jsonDecode(body);

      if (decoded is Map && decoded['error'] != null) {
        return decoded['error'].toString();
      }
    } catch (_) {
      // Ignore parse errors and fall back to raw body.
    }

    return body;
  }

  String _formatApiError(ApiException err) {
    final detail = _extractErrorMessage(err.body).trim();

    if (detail.isEmpty) {
      return 'HTTP ${err.statusCode}';
    }

    return 'HTTP ${err.statusCode}: $detail';
  }
}

// Forwarding preserves the existing library entry point and virtual dispatch.
mixin _DiagnosticsFacade {
  _DiagnosticsCoordinator get _diagnosticsCoordinator;

  StreamController<List<LogEntry>> get _messageController => _diagnosticsCoordinator._messageController;

  Timer? get _messageUpdateTimer => _diagnosticsCoordinator._messageUpdateTimer;

  set _messageUpdateTimer(Timer? value) => _diagnosticsCoordinator._messageUpdateTimer = value;

  Stream<List<LogEntry>> get messageStream => _diagnosticsCoordinator.messageStream;

  List<LogEntry> get messages => _diagnosticsCoordinator.messages;

  Future<void> clearMessages() => _diagnosticsCoordinator.clearMessages();

  void _pushMessage(String message, {LogLevel level = LogLevel.info}) =>
      _diagnosticsCoordinator._pushMessage(message, level: level);

  void _addLogEntry(LogEntry entry) => _diagnosticsCoordinator._addLogEntry(entry);

  String _formatApiError(ApiException err) => _diagnosticsCoordinator._formatApiError(err);
}
