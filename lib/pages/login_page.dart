import 'package:flutter/material.dart';

import '../entities/app_controller.dart';
import '../widgets/inputs/obsidian_text_field.dart';
import '../widgets/ui/obsidian_theme.dart';
import '../widgets/ui/obsidian_widgets.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with WidgetsBindingObserver {
  late final TextEditingController _serverHostController;
  late final TextEditingController _serverPortController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  bool _isSubmitting = false;
  String? _error;
  bool _connected = false;
  bool _useHttps = false;
  bool _normalizingAddress = false;
  bool _rememberMe = false;

  void _setStateIfMounted(VoidCallback fn) {
    if (!mounted) {
      return;
    }
    setState(fn);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _serverHostController = TextEditingController();
    _serverHostController.addListener(_handleServerHostChanged);
    _serverPortController = TextEditingController();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _serverHostController.removeListener(_handleServerHostChanged);
    _serverHostController.dispose();
    _serverPortController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.controller.refreshLocalNetworkPermission();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
            final minHeight =
                (constraints.maxHeight - 48 - keyboardInset).clamp(0.0, double.infinity);
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(0, 24, 0, 24 + keyboardInset),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ObsidianSectionHeader(
                            title: 'PHONOLITE',
                            subtitle: _connected
                                ? 'LOG IN'
                                : 'CONNECT TO SERVER',
                          ),
                          const SizedBox(height: 24),
                          _buildLocalNetworkWarning(),
                          if (!_connected) _buildServerSection(context),
                          if (_connected) ...[
                            _buildCredentialsSection(context),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            SelectableText(
                              _error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error),
                            ),
                          ],
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _isSubmitting ? null : _submit,
                            child: _isSubmitting
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Text(_connected ? 'Sign in' : 'Connect'),
                          ),
                          if (_connected)
                            TextButton(
                              onPressed: _isSubmitting
                                  ? null
                                  : () => setState(() {
                                        _connected = false;
                                        _error = null;
                                      }),
                              child: const Text('Change server'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final portValue = _parsePortInput();
    if (_serverPortController.text.trim().isNotEmpty && portValue == null) {
      _setStateIfMounted(() => _error = 'Port must be a number between 1 and 65535');
      return;
    }
    final baseUrl = _resolveBaseUrl();
    if (baseUrl.isEmpty) {
      _setStateIfMounted(() => _error = 'Server address is required');
      return;
    }

    _setStateIfMounted(() {
      _isSubmitting = true;
      _error = null;
    });

    if (!_connected) {
      final ok = await widget.controller.probeServer(baseUrl);
      _setStateIfMounted(() {
        _connected = ok;
        _isSubmitting = false;
        _error = ok ? null : widget.controller.authState.error ?? 'Connection failed';
      });
      return;
    }

    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    if (username.isEmpty || password.isEmpty) {
      _setStateIfMounted(() {
        _isSubmitting = false;
        _error = 'Username and password are required';
      });
      return;
    }

    await widget.controller.loginWithPassword(
      baseUrl: widget.controller.authState.baseUrl,
      username: username,
      password: password,
      rememberMe: _rememberMe,
    );

    _setStateIfMounted(() {
      _isSubmitting = false;
      if (!widget.controller.authState.isAuthorized) {
        final message = widget.controller.authState.error;
        _error = (message == null || message.trim().isEmpty)
            ? 'Login failed. Check credentials and server URL.'
            : message;
      } else {
        _error = null;
      }
    });
  }

  Widget _buildServerSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _SchemeToggle(
              value: _useHttps,
              enabled: !_connected,
              onChanged: (value) => setState(() => _useHttps = value),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ObsidianTextField(
          controller: _serverHostController,
          label: null,
          hintText: 'server.example.com',
          keyboardType: TextInputType.url,
          textInputAction: _connected ? TextInputAction.next : TextInputAction.next,
          enabled: !_connected,
          onSubmitted: null,
        ),
        const SizedBox(height: 12),
        ObsidianTextField(
          controller: _serverPortController,
          label: null,
          hintText: '3000',
          keyboardType: TextInputType.number,
          textInputAction: _connected ? TextInputAction.next : TextInputAction.done,
          enabled: !_connected,
          onSubmitted: _connected ? null : (_) => _submit(),
        ),
      ],
    );
  }

  Widget _buildCredentialsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ObsidianTextField(
          controller: _usernameController,
          label: 'Username',
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        ObsidianTextField(
          controller: _passwordController,
          label: 'Password',
          obscureText: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: _isSubmitting
              ? null
              : () => setState(() => _rememberMe = !_rememberMe),
          child: Row(
            children: [
              Checkbox(
                value: _rememberMe,
                onChanged: _isSubmitting
                    ? null
                    : (value) => setState(() => _rememberMe = value ?? false),
              ),
              const SizedBox(width: 6),
              Text(
                'Remember me',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: ObsidianPalette.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLocalNetworkWarning() {
    return StreamBuilder<LocalNetworkPermissionState>(
      stream: widget.controller.localNetworkPermissionStream,
      initialData: widget.controller.localNetworkPermissionState,
      builder: (context, snapshot) {
        final supported = widget.controller.localNetworkPermissionSupported ||
            Theme.of(context).platform == TargetPlatform.iOS;
        if (!supported) {
          return const SizedBox.shrink();
        }
        final state = snapshot.data ?? LocalNetworkPermissionState.unknown;
        final theme = Theme.of(context);
        final message = state == LocalNetworkPermissionState.denied
            ? 'Local network access is turned off. Enable it in iOS Settings to connect to servers on your network.'
            : 'Local network access hasn’t been granted yet. Enable it in iOS Settings if you can’t connect.';
        final showBanner = state != LocalNetworkPermissionState.granted;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showBanner) ...[
              GlassPanel(
                cut: 16,
                padding: const EdgeInsets.all(12),
                borderColor: theme.colorScheme.error.withOpacity(0.45),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.wifi_off_rounded, color: theme.colorScheme.error),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        message,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: ObsidianPalette.textMuted,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => widget.controller.openAppSettings(),
                  child: const Text('Open iOS Settings'),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              'Local network permission: ${state.name}',
              style: theme.textTheme.labelLarge?.copyWith(
                color: ObsidianPalette.textMuted,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }

  Future<void> _loadSavedCredentials() async {
    final saved = await widget.controller.loadSavedCredentials();
    if (!mounted || saved == null) {
      return;
    }
    final hasServer = _serverHostController.text.trim().isNotEmpty;
    final hasUsername = _usernameController.text.trim().isNotEmpty;
    if (!hasServer && saved.baseUrl.trim().isNotEmpty) {
      final parsed = Uri.tryParse(saved.baseUrl);
      if (parsed != null && parsed.scheme.isNotEmpty) {
        _useHttps = parsed.scheme == 'https';
      }
    }
    if (!hasUsername && saved.username.trim().isNotEmpty) {
      _usernameController.text = saved.username;
    }
    _setStateIfMounted(() {
      _rememberMe = true;
    });
  }

  void _initializeServerAddress(String baseUrl) {
    final parsed = Uri.tryParse(baseUrl);
    if (parsed != null && parsed.host.isNotEmpty) {
      _useHttps = parsed.scheme == 'https';
      final port = parsed.hasPort ? parsed.port.toString() : '';
      final path = _stripApiSuffix(parsed.path);
      final query = parsed.hasQuery ? '?${parsed.query}' : '';
      final pathValue = (path.isEmpty || path == '/') ? '' : path;
      _serverHostController.text = '${parsed.host}$pathValue$query';
      _serverPortController.text = port;
      return;
    }

    _useHttps = baseUrl.trimLeft().startsWith('https://');
    final withoutScheme = baseUrl.replaceFirst(RegExp(r'^https?://'), '');
    final cleaned = _stripApiSuffix(withoutScheme);
    final parts = _splitHostAndPort(cleaned);
    _serverHostController.text = parts.host;
    _serverPortController.text = parts.port ?? '';
  }

  void _handleServerHostChanged() {
    if (_normalizingAddress) {
      return;
    }
    final raw = _serverHostController.text;
    var value = raw.trim();
    if (value.isEmpty) {
      return;
    }
    final hasScheme =
        value.toLowerCase().startsWith('http://') || value.toLowerCase().startsWith('https://');
    if (hasScheme) {
      final isHttps = value.toLowerCase().startsWith('https://');
      if (_useHttps != isHttps) {
        _useHttps = isHttps;
        if (mounted) {
          setState(() {});
        }
      }
      value = value.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
    }
    value = value.replaceFirst(RegExp(r'^/+'), '');
    value = _stripApiSuffix(value);
    final parts = _splitHostAndPort(value);
    if (parts.port != null && parts.port != _serverPortController.text) {
      _serverPortController.text = parts.port!;
    }
    final normalized = parts.host;
    if (normalized != raw) {
      _normalizingAddress = true;
      _serverHostController.text = normalized;
      _serverHostController.selection =
          TextSelection.collapsed(offset: normalized.length);
      _normalizingAddress = false;
    }
  }

  String _resolveBaseUrl() {
    final raw = _serverHostController.text.trim();
    if (raw.isEmpty) {
      return '';
    }
    final sanitized = raw.replaceAll(RegExp(r'\s+'), '');
    final withoutScheme = sanitized.replaceFirst(RegExp(r'^https?://'), '');
    final cleaned = _stripApiSuffix(withoutScheme.replaceFirst(RegExp(r'^/+'), ''));
    if (cleaned.isEmpty) {
      return '';
    }
    final scheme = _useHttps ? 'https' : 'http';
    final parsed = Uri.tryParse('$scheme://$cleaned');
    if (parsed == null || parsed.host.isEmpty) {
      return '';
    }
    final port = _parsePortInput() ?? (parsed.hasPort ? parsed.port : null);
    final uri = Uri(
      scheme: scheme,
      userInfo: parsed.userInfo,
      host: parsed.host,
      port: port,
      path: parsed.path,
      query: parsed.query.isEmpty ? null : parsed.query,
    );
    return uri.toString();
  }

  String _stripApiSuffix(String input) {
    var value = input.trim();
    if (value.isEmpty) {
      return value;
    }
    value = value.replaceAll(RegExp(r'/+$'), '');
    value = value.replaceAll(RegExp(r'/api/v1$'), '');
    value = value.replaceAll(RegExp(r'/+$'), '');
    return value;
  }

  int? _parsePortInput() {
    final raw = _serverPortController.text.trim();
    if (raw.isEmpty) {
      return null;
    }
    final value = int.tryParse(raw);
    if (value == null || value < 1 || value > 65535) {
      return null;
    }
    return value;
  }

  _HostPortParts _splitHostAndPort(String input) {
    final sanitized = input.trim().replaceAll(RegExp(r'\s+'), '');
    if (sanitized.isEmpty) {
      return const _HostPortParts('', null);
    }
    final parsed = Uri.tryParse('http://$sanitized');
    if (parsed == null || parsed.host.isEmpty) {
      return _HostPortParts(sanitized, null);
    }
    final path = _stripApiSuffix(parsed.path);
    final query = parsed.hasQuery ? '?${parsed.query}' : '';
    final pathValue = (path.isEmpty || path == '/') ? '' : path;
    final hostValue = '${parsed.host}$pathValue$query';
    final portValue = parsed.hasPort ? parsed.port.toString() : null;
    return _HostPortParts(hostValue, portValue);
  }

}

class _HostPortParts {
  const _HostPortParts(this.host, this.port);

  final String host;
  final String? port;
}

class _SchemeToggle extends StatelessWidget {
  const _SchemeToggle({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  static const double _height = 40;

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _GlowToggleOption(
            label: 'HTTP',
            selected: !value,
            enabled: enabled,
            onTap: () => onChanged(false),
            height: _height,
          ),
          const SizedBox(width: 8),
          _GlowToggleOption(
            label: 'HTTPS',
            selected: value,
            enabled: enabled,
            onTap: () => onChanged(true),
            height: _height,
          ),
        ],
      ),
    );
  }
}

class _GlowToggleOption extends StatefulWidget {
  const _GlowToggleOption({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.height,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final double height;

  @override
  State<_GlowToggleOption> createState() => _GlowToggleOptionState();
}

class _GlowToggleOptionState extends State<_GlowToggleOption> {
  static const _transition = Duration(milliseconds: 160);
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) {
      return;
    }
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final baseBg = Colors.white.withOpacity(0.05);
    final baseBorder = Colors.white.withOpacity(0.12);
    final activeBorder = ObsidianPalette.gold.withOpacity(0.6);
    final highlight = widget.selected || _hovered;
    final bgColor = baseBg;
    final borderColor = highlight ? activeBorder : baseBorder;
    final textColor = widget.enabled
        ? (highlight ? ObsidianPalette.gold : ObsidianPalette.textMuted)
        : ObsidianPalette.textMuted.withOpacity(0.4);

    return MouseRegion(
      onEnter: widget.enabled ? (_) => _setHovered(true) : null,
      onExit: widget.enabled ? (_) => _setHovered(false) : null,
      cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: _transition,
          curve: Curves.easeOut,
          alignment: Alignment.center,
          constraints: BoxConstraints(minHeight: widget.height),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: bgColor,
            border: Border.all(color: borderColor),
            boxShadow: [
              if (highlight)
                BoxShadow(
                  color: ObsidianPalette.gold.withOpacity(0.35),
                  blurRadius: 10,
                ),
            ],
          ),
          child: AnimatedDefaultTextStyle(
            duration: _transition,
            curve: Curves.easeOut,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: textColor,
                  letterSpacing: 1.0,
                ) ??
                TextStyle(color: textColor),
            child: Text(widget.label),
          ),
        ),
      ),
    );
  }
}
