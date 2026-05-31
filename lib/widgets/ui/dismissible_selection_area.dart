import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;

class SelectionDismissLayer extends StatefulWidget {
  const SelectionDismissLayer({super.key, required this.child});

  final Widget child;

  @override
  State<SelectionDismissLayer> createState() => _SelectionDismissLayerState();
}

class _SelectionDismissLayerState extends State<SelectionDismissLayer> {
  int? _trackedPointer;
  Offset? _pointerStart;
  bool _hadSelectionAtPointerDown = false;
  bool _movedPastTapSlop = false;

  @override
  void initState() {
    super.initState();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_handlePointerEvent);
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(
      _handlePointerEvent,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  void _handlePointerEvent(PointerEvent event) {
    if (event is PointerDownEvent) {
      _handlePointerDown(event);
    } else if (event is PointerMoveEvent) {
      _handlePointerMove(event);
    } else if (event is PointerUpEvent) {
      _handlePointerUp(event);
    } else if (event is PointerCancelEvent) {
      _handlePointerCancel(event);
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_trackedPointer != null || !_isPrimaryPointer(event)) {
      return;
    }
    _trackedPointer = event.pointer;
    _pointerStart = event.position;
    _movedPastTapSlop = false;
    _hadSelectionAtPointerDown = _DismissibleSelectionRegistry.hasSelection;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final start = _pointerStart;
    if (event.pointer != _trackedPointer || start == null) {
      return;
    }
    if ((event.position - start).distance > kTouchSlop) {
      _movedPastTapSlop = true;
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    final shouldClear =
        event.pointer == _trackedPointer &&
        _hadSelectionAtPointerDown &&
        !_movedPastTapSlop;
    _resetPointerTracking();

    if (!shouldClear) {
      return;
    }
    scheduleMicrotask(() {
      if (mounted) {
        _DismissibleSelectionRegistry.clearSelections();
      }
    });
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer == _trackedPointer) {
      _resetPointerTracking();
    }
  }

  void _resetPointerTracking() {
    _trackedPointer = null;
    _pointerStart = null;
    _hadSelectionAtPointerDown = false;
    _movedPastTapSlop = false;
  }

  bool _isPrimaryPointer(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse ||
        event.kind == PointerDeviceKind.trackpad) {
      return event.buttons == kPrimaryButton;
    }
    return event.buttons == 0 || (event.buttons & kPrimaryButton) != 0;
  }
}

class DismissibleSelectionArea extends StatefulWidget {
  const DismissibleSelectionArea({
    super.key,
    required this.child,
    this.onSelectionChanged,
  });

  final Widget child;
  final ValueChanged<SelectedContent?>? onSelectionChanged;

  @override
  State<DismissibleSelectionArea> createState() =>
      _DismissibleSelectionAreaState();
}

class _DismissibleSelectionAreaState extends State<DismissibleSelectionArea> {
  final GlobalKey<SelectionAreaState> _selectionAreaKey =
      GlobalKey<SelectionAreaState>();
  bool _hasSelection = false;

  bool get hasSelection => _hasSelection;

  @override
  void initState() {
    super.initState();
    _DismissibleSelectionRegistry.register(this);
  }

  @override
  void dispose() {
    _DismissibleSelectionRegistry.unregister(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      key: _selectionAreaKey,
      onSelectionChanged: _handleSelectionChanged,
      child: widget.child,
    );
  }

  void clearSelection() {
    if (!_hasSelection) {
      return;
    }
    _hasSelection = false;
    final selectableRegion = _selectionAreaKey.currentState?.selectableRegion;
    selectableRegion?.hideToolbar();
    selectableRegion?.clearSelection();
  }

  void _handleSelectionChanged(SelectedContent? content) {
    _hasSelection = content?.plainText.isNotEmpty ?? false;
    widget.onSelectionChanged?.call(content);
  }
}

class _DismissibleSelectionRegistry {
  static final Set<_DismissibleSelectionAreaState> _areas =
      <_DismissibleSelectionAreaState>{};

  static bool get hasSelection => _areas.any((area) => area.hasSelection);

  static void register(_DismissibleSelectionAreaState area) {
    _areas.add(area);
  }

  static void unregister(_DismissibleSelectionAreaState area) {
    _areas.remove(area);
  }

  static void clearSelections() {
    for (final area in _areas.toList(growable: false)) {
      if (area.mounted) {
        area.clearSelection();
      }
    }
  }
}
