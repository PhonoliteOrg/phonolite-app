import 'package:flutter/material.dart';

import '../widgets/layouts/playback_content_inset.dart';

import '../entities/app_controller.dart';
import '../widgets/inputs/lucide_checkbox.dart';
import '../widgets/inputs/obsidian_text_field.dart';
import '../widgets/layout/library_header.dart';
import '../widgets/modals/modal_action_button.dart';
import '../widgets/modals/obsidian_dialog.dart';
import '../widgets/modals/obsidian_modal_scope.dart';
import '../widgets/navigation/command_link_button.dart';
import '../widgets/ui/obsidian_theme.dart';
import '../widgets/ui/button_haptics.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.controller});

  static const routeName = '/login';

  static Route<void> route(AppController controller) {
    return MaterialPageRoute<void>(
      settings: const RouteSettings(name: routeName),
      builder: (_) => LoginPage(controller: controller),
    );
  }

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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          20,
          16 + PlaybackContentInset.topOf(context),
          20,
          20 +
              PlaybackContentInset.bottomOf(context) +
              MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (Navigator.of(context).canPop()) ...[
              CommandLinkButton(
                label: 'Back to settings',
                onTap: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 12),
            ],
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LibraryHeader(
                      title: (_connected ? 'Sign in' : 'Connect to server')
                          .toUpperCase(),
                      moduleCount: 0,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 24),
                    // Use the same readable fields and touch targets as modals.
                    ObsidianModalScope(builder: _buildForm),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _connected
              ? 'Use your server account to finish connecting.'
              : 'Enter the address of the server you want to use.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: ObsidianPalette.textMuted),
        ),
        const SizedBox(height: 24),
        _buildLocalNetworkSettings(),
        if (_connected)
          _buildCredentialsSection(context)
        else
          _buildServerSection(context),
        if (_error != null) ...[
          const SizedBox(height: 16),
          SelectableText(
            _error!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 20),
        ObsidianModalActions(
          children: [
            if (_connected)
              ModalActionButton(
                label: 'Change server',
                onPressed: _isSubmitting
                    ? null
                    : () => setState(() {
                        _connected = false;
                        _error = null;
                      }),
              ),
            Stack(
              alignment: Alignment.center,
              children: [
                Visibility(
                  visible: !_isSubmitting,
                  maintainSize: true,
                  maintainState: true,
                  maintainAnimation: true,
                  child: ModalActionButton(
                    label: _connected ? 'Sign in' : 'Connect',
                    onPressed: _isSubmitting ? null : _submit,
                  ),
                ),
                if (_isSubmitting)
                  Positioned.fill(
                    child: Center(
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          semanticsLabel: _connected
                              ? 'Signing in'
                              : 'Connecting',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (_isSubmitting) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();

    final portValue = _parsePortInput();
    if (_serverPortController.text.trim().isNotEmpty && portValue == null) {
      _setStateIfMounted(
        () => _error = 'Port must be a number between 1 and 65535',
      );
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
        _error = ok
            ? null
            : widget.controller.authState.error ?? 'Connection failed';
      });
      return;
    }

    final username = _usernameController.text.trim();
    final password = _passwordController.text;
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
    if (mounted && widget.controller.authState.isAuthorized) {
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop();
      }
    }
  }

  Widget _buildServerSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInput(
          context,
          controller: _serverHostController,
          label: 'Server address',
          hintText: 'server.example.com',
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
        ),
        const SizedBox(height: 20),
        _buildInput(
          context,
          controller: _serverPortController,
          label: 'Port',
          hintText: '3000',
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
      ],
    );
  }

  Widget _buildCredentialsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInput(
          context,
          controller: _usernameController,
          label: 'Username',
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
        ),
        const SizedBox(height: 20),
        _buildInput(
          context,
          controller: _passwordController,
          label: 'Password',
          obscureText: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: withButtonHaptic(
            _isSubmitting
                ? null
                : () => setState(() => _rememberMe = !_rememberMe),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Row(
              children: [
                LucideCheckbox(
                  value: _rememberMe,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  visualDensity: VisualDensity.standard,
                  onChanged: _isSubmitting
                      ? null
                      : (value) => setState(() => _rememberMe = value ?? false),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Remember me',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: ObsidianPalette.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInput(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    String? hintText,
    bool obscureText = false,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
  }) {
    return ObsidianTextField(
      controller: controller,
      label: label,
      hintText: hintText,
      height: ObsidianModalScope.usesTouchTargets(context) ? 56 : 48,
      cut: 0,
      startPadding: 24,
      isDense: true,
      enabled: !_isSubmitting,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
    );
  }

  Widget _buildLocalNetworkSettings() {
    return StreamBuilder<LocalNetworkPermissionState>(
      stream: widget.controller.localNetworkPermissionStream,
      initialData: widget.controller.localNetworkPermissionState,
      builder: (context, snapshot) {
        final supported =
            widget.controller.localNetworkPermissionSupported ||
            Theme.of(context).platform == TargetPlatform.iOS;
        if (!supported) {
          return const SizedBox.shrink();
        }
        final state = snapshot.data ?? LocalNetworkPermissionState.unknown;
        final theme = Theme.of(context);
        final needsSettings = state != LocalNetworkPermissionState.granted;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (needsSettings) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: withButtonHaptic(
                    () => widget.controller.openAppSettings(),
                  ),
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
      _initializeServerAddress(saved.baseUrl);
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
      final port = parsed.hasPort ? parsed.port.toString() : '';
      final path = _stripApiSuffix(parsed.path);
      final query = parsed.hasQuery ? '?${parsed.query}' : '';
      final pathValue = (path.isEmpty || path == '/') ? '' : path;
      _serverHostController.text = '${parsed.host}$pathValue$query';
      _serverPortController.text = port;
      return;
    }

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
        value.toLowerCase().startsWith('http://') ||
        value.toLowerCase().startsWith('https://');
    if (hasScheme) {
      value = value.replaceFirst(
        RegExp(r'^https?://', caseSensitive: false),
        '',
      );
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
      _serverHostController.selection = TextSelection.collapsed(
        offset: normalized.length,
      );
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
    final cleaned = _stripApiSuffix(
      withoutScheme.replaceFirst(RegExp(r'^/+'), ''),
    );
    if (cleaned.isEmpty) {
      return '';
    }
    const scheme = 'https';
    final parsed = Uri.tryParse('$scheme://$cleaned');
    if (parsed == null || parsed.host.isEmpty) {
      return '';
    }
    final port = _parsePortInput() ?? (parsed.hasPort ? parsed.port : 3000);
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
    final host = parsed.host.contains(':') ? '[${parsed.host}]' : parsed.host;
    final hostValue = '$host$pathValue$query';
    final portValue = parsed.hasPort ? parsed.port.toString() : null;
    return _HostPortParts(hostValue, portValue);
  }
}

class _HostPortParts {
  const _HostPortParts(this.host, this.port);

  final String host;
  final String? port;
}
