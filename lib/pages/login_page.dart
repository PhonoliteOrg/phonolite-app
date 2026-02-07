import 'package:flutter/material.dart';

import '../entities/app_controller.dart';
import '../widgets/inputs/auth_text_field.dart';
import '../widgets/ui/obsidian_theme.dart';
import '../widgets/ui/obsidian_widgets.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final TextEditingController _baseUrlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _tokenController;

  bool _useToken = false;
  bool _isSubmitting = false;
  String? _error;
  bool _connected = false;

  void _setStateIfMounted(VoidCallback fn) {
    if (!mounted) {
      return;
    }
    setState(fn);
  }

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(text: widget.controller.authState.baseUrl);
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _tokenController = TextEditingController();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: GlassPanel(
              cut: 20,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ObsidianSectionHeader(
                    title: 'PHONOLITE',
                    subtitle: _connected ? 'AUTHENTICATION READY' : 'CONNECT TO SERVER',
                  ),
                  const SizedBox(height: 24),
                  AuthTextField(
                    controller: _baseUrlController,
                    label: 'Server URL',
                    hintText: 'http://127.0.0.1:3000/api/v1',
                  ),
                  const SizedBox(height: 12),
                  if (_connected) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Connected: ${widget.controller.authState.baseUrl}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: ObsidianPalette.textMuted),
                      ),
                    ),
                    SwitchListTile(
                      value: _useToken,
                      title: const Text('Use token instead of username/password'),
                      onChanged: (value) => setState(() => _useToken = value),
                      activeColor: ObsidianPalette.gold,
                    ),
                    if (_useToken) ...[
                      AuthTextField(
                        controller: _tokenController,
                        label: 'Token',
                      ),
                    ] else ...[
                      AuthTextField(
                        controller: _usernameController,
                        label: 'Username',
                      ),
                      const SizedBox(height: 12),
                      AuthTextField(
                        controller: _passwordController,
                        label: 'Password',
                        obscureText: true,
                      ),
                    ],
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    SelectableText(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
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
  }

  Future<void> _submit() async {
    final baseUrl = _baseUrlController.text.trim();
    if (baseUrl.isEmpty) {
      _setStateIfMounted(() => _error = 'Server URL is required');
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

    if (_useToken) {
      final token = _tokenController.text.trim();
      if (token.isEmpty) {
        _setStateIfMounted(() {
          _isSubmitting = false;
          _error = 'Token is required';
        });
        return;
      }
      widget.controller.loginWithToken(
        baseUrl: widget.controller.authState.baseUrl,
        token: token,
      );
      _setStateIfMounted(() => _isSubmitting = false);
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
}
