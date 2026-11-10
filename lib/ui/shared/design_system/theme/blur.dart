import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

bool enableBackdropBlur() {
  return !kIsWeb && defaultTargetPlatform != TargetPlatform.windows;
}

Widget maybeBlur({required double sigma, required Widget child}) {
  if (sigma <= 0 || !enableBackdropBlur()) {
    return child;
  }

  return Builder(
    builder: (context) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      enabled: !BackdropBlurResizeSuspension.isSuspended(context),
      child: child,
    ),
  );
}

/// Pauses backdrop blur while a desktop window is being resized.
///
/// Every resize step must render a complete frame before the window can take
/// the next size. On an Intel Mac with Skia, backdrop blur pushed those frames
/// from about 17 ms to 29 ms, so resizing ran at half the display rate. Blur
/// returns once the size has been stable for [settle]; resting frames are
/// unaffected. Filters stay mounted and are only disabled, so descendants keep
/// their state.
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

    if (previous == null || previous == size || !_isDesktop(Theme.of(context).platform)) {
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

  static bool _isDesktop(TargetPlatform platform) => switch (platform) {
    TargetPlatform.macOS || TargetPlatform.windows || TargetPlatform.linux => true,
    TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => false,
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
