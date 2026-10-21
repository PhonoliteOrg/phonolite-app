import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/feature_controller.dart';
import 'package:phonolite_app/data/models/auth/auth_credentials.dart';
import 'package:phonolite_app/data/models/auth/host_port_parts.dart';

export 'package:phonolite_app/data/models/auth/host_port_parts.dart';

class LoginController extends FeatureController {
  final AppController app;
  bool _isSubmitting = false;
  String? _error;
  bool _connected = false;
  bool _rememberMe = false;

  LoginController(this.app) {
    if (app.authState.requiresSignIn) {
      _connected = true;
      _error = app.authState.error;
    }
  }

  bool get isSubmitting => _isSubmitting;

  String? get error => _error;

  bool get connected => _connected;

  bool get rememberMe => _rememberMe;

  Future<bool> changeServer() async {
    if (_isSubmitting) {
      return false;
    }

    update(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await app.logout();
      update(() {
        _resetServerConnection();
        _rememberMe = false;
      });
      return true;
    } catch (_) {
      update(() => _error = 'Could not disconnect from this server. Try again.');
      return false;
    } finally {
      update(() => _isSubmitting = false);
    }
  }

  void setRememberMe(bool value) => update(() => _rememberMe = value);

  Future<AuthCredentials?> loadSavedCredentials() async {
    final saved = await app.loadSavedCredentials();

    if (saved != null) {
      update(() => _rememberMe = true);
    }

    return saved;
  }

  Future<bool> submit({
    required String host,
    required String port,
    required String username,
    required String password,
  }) async {
    if (_isSubmitting) {
      return false;
    }

    final portValue = parsePortInput(port);

    if (port.trim().isNotEmpty && portValue == null) {
      update(() => _error = 'Port must be a number between 1 and 65535');

      return false;
    }

    final baseUrl = _connected ? app.authState.baseUrl : resolveBaseUrl(host, port);

    if (baseUrl.isEmpty) {
      update(() => _error = 'Server address is required');

      return false;
    }

    void beginSubmission() {
      _isSubmitting = true;
      _error = null;
    }

    update(beginSubmission);

    if (!_connected) {
      final ok = await app.probeServer(baseUrl);

      void publishProbeResult() {
        _connected = ok;
        _isSubmitting = false;
        _error = ok ? null : app.authState.error ?? 'Connection failed';
      }

      update(publishProbeResult);

      return false;
    }

    username = username.trim();

    if (username.isEmpty || password.isEmpty) {
      void showMissingCredentials() {
        _isSubmitting = false;
        _error = 'Username and password are required';
      }

      update(showMissingCredentials);

      return false;
    }

    await app.loginWithPassword(
      baseUrl: app.authState.baseUrl,
      username: username,
      password: password,
      rememberMe: _rememberMe,
    );

    void publishLoginResult() {
      _isSubmitting = false;

      if (!app.authState.isAuthorized) {
        final message = app.authState.error;

        _error = (message == null || message.trim().isEmpty)
            ? 'Login failed. Check credentials and server URL.'
            : message;
      } else {
        _error = null;
      }
    }

    update(publishLoginResult);

    return app.authState.isAuthorized;
  }

  String resolveBaseUrl(String host, String port) {
    final raw = host.trim();

    if (raw.isEmpty) {
      return '';
    }

    final sanitized = raw.replaceAll(RegExp(r'\s+'), '');
    final withoutScheme = sanitized.replaceFirst(RegExp(r'^https?://'), '');
    final cleaned = stripApiSuffix(withoutScheme.replaceFirst(RegExp(r'^/+'), ''));

    if (cleaned.isEmpty) {
      return '';
    }

    const scheme = 'https';
    final parsed = Uri.tryParse('$scheme://$cleaned');

    if (parsed == null || parsed.host.isEmpty) {
      return '';
    }

    final resolvedPort = parsePortInput(port) ?? (parsed.hasPort ? parsed.port : 3000);
    final uri = Uri(
      scheme: scheme,
      userInfo: parsed.userInfo,
      host: parsed.host,
      port: resolvedPort,
      path: parsed.path,
      query: parsed.query.isEmpty ? null : parsed.query,
    );

    return uri.toString();
  }

  String stripApiSuffix(String input) {
    var value = input.trim();

    if (value.isEmpty) {
      return value;
    }

    value = value.replaceAll(RegExp(r'/+$'), '');
    value = value.replaceAll(RegExp(r'/api$'), '');
    value = value.replaceAll(RegExp(r'/+$'), '');

    return value;
  }

  int? parsePortInput(String port) {
    final raw = port.trim();

    if (raw.isEmpty) {
      return null;
    }

    final value = int.tryParse(raw);

    if (value == null || value < 1 || value > 65535) {
      return null;
    }

    return value;
  }

  HostPortParts splitHostAndPort(String input) {
    final sanitized = input.trim().replaceAll(RegExp(r'\s+'), '');

    if (sanitized.isEmpty) {
      return const HostPortParts('', null);
    }

    final parsed = Uri.tryParse('http://$sanitized');

    if (parsed == null || parsed.host.isEmpty) {
      return HostPortParts(sanitized, null);
    }

    final path = stripApiSuffix(parsed.path);
    final query = parsed.hasQuery ? '?${parsed.query}' : '';
    final pathValue = (path.isEmpty || path == '/') ? '' : path;
    final host = parsed.host.contains(':') ? '[${parsed.host}]' : parsed.host;
    final hostValue = '$host$pathValue$query';
    final portValue = parsed.hasPort ? parsed.port.toString() : null;

    return HostPortParts(hostValue, portValue);
  }

  HostPortParts savedAddress(String baseUrl) {
    final parsed = Uri.tryParse(baseUrl);

    if (parsed != null && parsed.host.isNotEmpty) {
      final port = parsed.port.toString();
      final host = parsed.host.contains(':') ? '[${parsed.host}]' : parsed.host;
      final path = stripApiSuffix(parsed.path);
      final query = parsed.hasQuery ? '?${parsed.query}' : '';
      final pathValue = (path.isEmpty || path == '/') ? '' : path;

      return HostPortParts('$host$pathValue$query', port);
    }

    final withoutScheme = baseUrl.replaceFirst(RegExp(r'^https?://'), '');
    final cleaned = stripApiSuffix(withoutScheme);

    return splitHostAndPort(cleaned);
  }

  HostPortParts normalizeAddress(String raw) {
    var value = raw.trim();

    if (value.isEmpty) {
      return const HostPortParts('', null);
    }

    final hasScheme = value.toLowerCase().startsWith('http://') || value.toLowerCase().startsWith('https://');

    if (hasScheme) {
      value = value.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
    }

    value = value.replaceFirst(RegExp(r'^/+'), '');
    value = stripApiSuffix(value);

    return splitHostAndPort(value);
  }

  void _resetServerConnection() {
    _connected = false;
    _error = null;
  }
}
