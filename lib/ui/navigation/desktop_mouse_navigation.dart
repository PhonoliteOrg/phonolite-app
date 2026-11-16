import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'package:phonolite_app/ui/navigation/desktop_input_policy.dart';

/// Maps mouse side buttons and macOS trackpad swipes to menu navigation.
class DesktopMouseNavigation extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onForward;
  final Widget child;

  const DesktopMouseNavigation({super.key, required this.onBack, required this.onForward, required this.child});

  void _handlePointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse) {
      return;
    }

    switch (event.buttons) {
      case kBackMouseButton:
        onBack();
      case kForwardMouseButton:
        onForward();
    }
  }

  void _handleSwipe(double horizontalTravel) {
    if (horizontalTravel > 0) {
      onBack();
    } else {
      onForward();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!desktopInputEnabled) {
      return child;
    }

    final content = defaultTargetPlatform == TargetPlatform.macOS
        ? RawGestureDetector(
            excludeFromSemantics: true,
            gestures: {
              _TrackpadNavigationGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<_TrackpadNavigationGestureRecognizer>(
                    _TrackpadNavigationGestureRecognizer.new,
                    (recognizer) => recognizer.onSwipe = _handleSwipe,
                  ),
            },
            child: child,
          )
        : child;

    return Listener(behavior: HitTestBehavior.opaque, onPointerDown: _handlePointerDown, child: content);
  }
}

/// Lets scrollables win normal drags before claiming a page swipe.
class _TrackpadNavigationGestureRecognizer extends OneSequenceGestureRecognizer {
  static const double _minimumTravel = 80;
  static const double _horizontalRatio = 2;

  late ValueChanged<double> onSwipe;
  int? _pointer;
  Offset _pan = Offset.zero;
  bool _accepted = false;

  _TrackpadNavigationGestureRecognizer() : super(supportedDevices: const {PointerDeviceKind.trackpad});

  @override
  String get debugDescription => 'trackpad page swipe';

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    if (_pointer != null) {
      return;
    }

    _pointer = event.pointer;
    startTrackingPointer(event.pointer, event.transform);
  }

  @override
  void acceptGesture(int pointer) {
    _accepted = true;
  }

  @override
  void rejectGesture(int pointer) => stopTrackingPointer(pointer);

  @override
  void handleNonAllowedPointer(PointerDownEvent event) {
    if (_pointer case final pointer?) {
      stopTrackingPointer(pointer);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    switch (event) {
      case PointerPanZoomUpdateEvent():
        _update(event);
      case PointerPanZoomEndEvent():
        final delta = _pan.dx;
        final completesSwipe = _accepted && _isSwipe;
        stopTrackingPointer(event.pointer);

        if (completesSwipe) {
          invokeCallback('onSwipe', () => onSwipe(delta));
        }
      case PointerCancelEvent():
        stopTrackingPointer(event.pointer);
    }
  }

  void _update(PointerPanZoomUpdateEvent event) {
    _pan = event.localPan;
    final verticalDrag = _pan.dy.abs() > kTouchSlop && _pan.dy.abs() >= _pan.dx.abs();

    if (event.scale != 1 || event.rotation != 0 || verticalDrag) {
      stopTrackingPointer(event.pointer);

      return;
    }

    if (_isSwipe) {
      resolvePointer(event.pointer, GestureDisposition.accepted);
    }
  }

  bool get _isSwipe => _pan.dx.abs() >= _minimumTravel && _pan.dx.abs() >= _pan.dy.abs() * _horizontalRatio;

  @override
  void didStopTrackingLastPointer(int pointer) {
    _pointer = null;
    _pan = Offset.zero;
    _accepted = false;
    resolvePointer(pointer, GestureDisposition.rejected);
  }
}
