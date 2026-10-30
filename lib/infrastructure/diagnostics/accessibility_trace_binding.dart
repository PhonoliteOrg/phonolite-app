import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'package:phonolite_app/infrastructure/diagnostics/accessibility_update_trace.dart';

/// Observes the normal binding's accessibility updates without requesting them.
class AccessibilityTraceBinding extends WidgetsFlutterBinding {
  final AccessibilityUpdateTrace _trace;

  AccessibilityTraceBinding({required void Function(String) write}) : _trace = AccessibilityUpdateTrace(write: write) {
    addSemanticsEnabledListener(_handleSemanticsEnabledChanged);
  }

  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() => _trace.wrap(super.createSemanticsUpdateBuilder());

  void _handleSemanticsEnabledChanged() {
    if (!semanticsEnabled) {
      _trace.reset();
    }
  }
}
