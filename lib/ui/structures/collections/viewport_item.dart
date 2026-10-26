import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Cache-extent children stay lightweight. Activate work only when a tile
/// intersects the viewport, and defer new work until scrolling settles.
class ViewportItem extends StatefulWidget {
  final Widget Function(BuildContext, bool visible) builder;
  final ValueChanged<bool> onVisibilityChanged;

  const ViewportItem({super.key, required this.builder, required this.onVisibilityChanged});

  @override
  State<ViewportItem> createState() => _ViewportItemState();
}

class _ViewportItemState extends State<ViewportItem> {
  ScrollPosition? _position;
  bool _active = false;
  bool _routeActive = true;
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _position) {
      _unlisten();
      _position = position;
      position?.addListener(_scheduleCheck);
      position?.isScrollingNotifier.addListener(_scheduleCheck);
    }
    _routeActive = TickerMode.of(context) && (ModalRoute.of(context)?.isCurrent ?? true);
    _scheduleCheck();
  }

  @override
  void didUpdateWidget(ViewportItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleCheck();
  }

  void _unlisten() {
    _position?.removeListener(_scheduleCheck);
    _position?.isScrollingNotifier.removeListener(_scheduleCheck);
  }

  void _scheduleCheck() {
    if (_scheduled || !mounted) {
      return;
    }
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) {
        _check();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _check() {
    final box = context.findRenderObject();
    var visible = _routeActive && box is RenderBox && box.hasSize && box.attached;
    if (visible) {
      final viewport = RenderAbstractViewport.maybeOf(box);
      if (viewport != null) {
        final bounds = MatrixUtils.transformRect(box.getTransformTo(viewport), box.paintBounds);
        visible = bounds.overlaps(viewport.paintBounds);
      }
    }
    // Keep existing on-screen content during a drag; new arrivals wait for idle.
    final active = visible && (_active || !(_position?.isScrollingNotifier.value ?? false));
    if (active != _active) {
      setState(() => _active = active);
      widget.onVisibilityChanged(active);
    }
  }

  @override
  void dispose() {
    _unlisten();
    if (_active) {
      widget.onVisibilityChanged(false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _active);
}
