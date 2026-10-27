import 'package:flutter/material.dart';

import 'package:phonolite_app/application/app/app_controller.dart';
import 'package:phonolite_app/application/controllers/auth/login_controller.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/lucide_checkbox.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_text_field.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/button_haptics.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/modal_action_button.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_dialog.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';
import 'package:phonolite_app/ui/shell/base_form_page.dart';
import 'package:phonolite_app/ui/shell/base_page.dart';

class LoginPage extends BasePage {
  static const String routeName = '/login';

  final AppController controller;

  const LoginPage({super.key, required this.controller});

  static Route<void> route(AppController controller) {
    return MaterialPageRoute<void>(
      settings: const RouteSettings(name: routeName),
      builder: (_) => LoginPage(controller: controller),
    );
  }

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends BaseFormPageState<LoginPage> with WidgetsBindingObserver {
  late final LoginController _feature = bindController(LoginController(widget.controller));
  late final TextEditingController _serverHostController;
  late final TextEditingController _serverPortController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  bool _normalizingAddress = false;

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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.controller.refreshLocalNetworkPermission();
    }
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
  String pageTitle(BuildContext context) => (_feature.connected ? 'Sign in' : 'Connect to server').toUpperCase();

  @override
  bool showBackButton(BuildContext context) => Navigator.of(context).canPop();

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
          onTap: withButtonHaptic(_feature.isSubmitting ? null : () => _feature.setRememberMe(!_feature.rememberMe)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Row(
              children: [
                LucideCheckbox(
                  value: _feature.rememberMe,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  visualDensity: VisualDensity.standard,
                  onChanged: _feature.isSubmitting ? null : (value) => _feature.setRememberMe(value ?? false),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Remember me',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: ObsidianPalette.textMuted),
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
      enabled: !_feature.isSubmitting,
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
            widget.controller.localNetworkPermissionSupported || Theme.of(context).platform == TargetPlatform.iOS;

        if (!supported) {
          return const SizedBox.shrink();
        }

        final state = snapshot.data ?? LocalNetworkPermissionState.unknown;
        if (state == LocalNetworkPermissionState.granted) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: withButtonHaptic(() => widget.controller.openAppSettings()),
                child: const Text('Open iOS Settings'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Local network permission: ${state.name}',
              style: theme.textTheme.labelLarge?.copyWith(color: ObsidianPalette.textMuted, letterSpacing: 1.1),
            ),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();

    final authorized = await _feature.submit(
      host: _serverHostController.text,
      port: _serverPortController.text,
      username: _usernameController.text,
      password: _passwordController.text,
    );

    if (mounted && authorized && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _changeServer() async {
    FocusManager.instance.primaryFocus?.unfocus();

    final changed = await _feature.changeServer();
    if (mounted && changed) {
      _serverHostController.clear();
      _serverPortController.clear();
      _usernameController.clear();
      _passwordController.clear();
    }
  }

  void _handleServerHostChanged() {
    if (_normalizingAddress) {
      return;
    }

    final raw = _serverHostController.text;
    final address = _feature.normalizeAddress(raw);

    if (address.port != null && address.port != _serverPortController.text) {
      _serverPortController.text = address.port!;
    }

    if (address.host != raw) {
      _normalizingAddress = true;
      _serverHostController.value = TextEditingValue(
        text: address.host,
        selection: TextSelection.collapsed(offset: address.host.length),
      );
      _normalizingAddress = false;
    }
  }

  Future<void> _loadSavedCredentials() async {
    final saved = await _feature.loadSavedCredentials();

    if (!mounted) {
      return;
    }

    final hasUsername = _usernameController.text.trim().isNotEmpty;

    if (!hasUsername && saved != null && saved.username.trim().isNotEmpty) {
      _usernameController.text = saved.username;
    }
  }

  @override
  Widget formContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _feature.connected
              ? 'Use your server account to finish connecting.'
              : 'Enter the address of the server you want to use.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: ObsidianPalette.textMuted),
        ),
        const SizedBox(height: 24),
        _buildLocalNetworkSettings(),
        if (_feature.connected) _buildCredentialsSection(context) else _buildServerSection(context),
        if (_feature.error != null) ...[
          const SizedBox(height: 16),
          SelectableText(
            _feature.error!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 20),
        ObsidianModalActions(
          children: [
            if (_feature.connected)
              ModalActionButton(label: 'Change server', onPressed: _feature.isSubmitting ? null : _changeServer),
            Stack(
              alignment: Alignment.center,
              children: [
                Visibility(
                  visible: !_feature.isSubmitting,
                  maintainSize: true,
                  maintainState: true,
                  maintainAnimation: true,
                  child: ModalActionButton(
                    label: _feature.connected ? 'Sign in' : 'Connect',
                    onPressed: _feature.isSubmitting ? null : _submit,
                  ),
                ),
                if (_feature.isSubmitting)
                  Positioned.fill(
                    child: Center(
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          semanticsLabel: _feature.connected ? 'Signing in' : 'Connecting',
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
}
