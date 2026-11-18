import 'dart:async';

import 'package:flutter/material.dart';

/// Pauses backdrop blur while a Windows or Linux window is being resized.
///
/// Blur returns once the size has been stable for [settle]. Filters stay
/// mounted so descendants keep their state. macOS keeps blur active for a
/// consistent glass appearance throughout the resize.
class BackdropBlurResizeSuspension extends StatefulWidget {
  static const Duration defaultSettle = Duration(milliseconds: 200);

  final Duration settle;
  final Widget child;

  const BackdropBlurResizeSuspension({super.key, this.settle = defaultSettle, required this.child});

  static bool isSuspended(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_BlurSuspended>()?.suspended ?? false;

  @override
  State<BackdropBlurResizeSuspension> createState() => _BackdropBlurResizeSuspensionState();
}

class _BackdropBlurResizeSuspensionState extends State<BackdropBlurResizeSuspension> {
  Size? _size;
  bool _suspended = false;
  Timer? _settle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final size = MediaQuery.sizeOf(context);
    final previous = _size;
    _size = size;

    if (previous == null || previous == size || !_suspendsOnResize(Theme.of(context).platform)) {
      return;
    }

    // A dependency change is always followed by a rebuild, so no setState.
    _suspended = true;
    _settle?.cancel();
    _settle = Timer(widget.settle, _resume);
  }

  @override
  void dispose() {
    _settle?.cancel();

    super.dispose();
  }

  void _resume() {
    if (mounted) {
      setState(() => _suspended = false);
    }
  }

  static bool _suspendsOnResize(TargetPlatform platform) => switch (platform) {
    TargetPlatform.windows || TargetPlatform.linux => true,
    TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia || TargetPlatform.macOS => false,
  };

  @override
  Widget build(BuildContext context) => _BlurSuspended(suspended: _suspended, child: widget.child);
}

class _BlurSuspended extends InheritedWidget {
  final bool suspended;

  const _BlurSuspended({required this.suspended, required super.child});

  @override
  bool updateShouldNotify(_BlurSuspended oldWidget) => oldWidget.suspended != suspended;
}
