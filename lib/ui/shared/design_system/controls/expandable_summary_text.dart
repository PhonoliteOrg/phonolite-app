import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/interaction/button_haptics.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/dismissible_selection_area.dart';

class ExpandableSummaryText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Color toggleColor;
  final double collapsedMaxHeight;
  final int collapsedMaxLines;
  final int toggleThreshold;
  final EdgeInsetsGeometry togglePadding;

  const ExpandableSummaryText({
    super.key,
    required this.text,
    required this.style,
    required this.toggleColor,
    this.collapsedMaxHeight = 72,
    this.collapsedMaxLines = 3,
    this.toggleThreshold = 140,
    this.togglePadding = EdgeInsets.zero,
  });

  @override
  State<ExpandableSummaryText> createState() => _ExpandableSummaryTextState();
}

class _ExpandableSummaryTextState extends State<ExpandableSummaryText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final showToggle = widget.text.length > widget.toggleThreshold;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRect(
          child: ConstrainedBox(
            constraints: _expanded ? const BoxConstraints() : BoxConstraints(maxHeight: widget.collapsedMaxHeight),
            child: DefaultSelectionStyle(
              selectionColor: widget.toggleColor.withValues(alpha: 0.35),
              child: DismissibleSelectionArea(
                child: Text(
                  widget.text,
                  overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                  maxLines: _expanded ? null : widget.collapsedMaxLines,
                  softWrap: true,
                  style: widget.style,
                ),
              ),
            ),
          ),
        ),
        if (showToggle)
          TextButton(
            onPressed: withButtonHaptic(() => setState(() => _expanded = !_expanded)),
            style: TextButton.styleFrom(foregroundColor: widget.toggleColor, padding: widget.togglePadding),
            child: Text(_expanded ? 'Collapse' : 'Read more'),
          ),
      ],
    );
  }
}
