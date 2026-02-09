import 'package:flutter/material.dart';

import '../ui/obsidian_theme.dart';
import '../ui/obsidian_widgets.dart';

class MessageLog extends StatefulWidget {
  const MessageLog({
    super.key,
    required this.messages,
    this.onClear,
    this.title = 'Messages',
    this.subtitle,
    this.trailing,
  });

  final List<String> messages;
  final VoidCallback? onClear;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  State<MessageLog> createState() => _MessageLogState();
}

class _MessageLogState extends State<MessageLog> {
  final FocusNode _selectionFocus = FocusNode();

  @override
  void dispose() {
    _selectionFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final defaultSubtitle =
        widget.messages.isEmpty ? 'No events yet' : 'System log';
    final trailing = widget.trailing ??
        (widget.onClear == null
            ? null
            : TextButton.icon(
                onPressed: widget.onClear,
                icon: const Icon(Icons.clear_all_rounded),
                label: const Text('Clear'),
              ));

    return Column(
      children: [
        ObsidianSectionHeader(
          title: widget.title,
          subtitle: widget.subtitle ?? defaultSubtitle,
          trailing: trailing,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: GlassPanel(
            cut: 18,
            padding: const EdgeInsets.all(12),
            child: SelectableRegion(
              focusNode: _selectionFocus,
              selectionControls: materialTextSelectionControls,
              child: ListView.separated(
                itemCount: widget.messages.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: ObsidianPalette.border.withOpacity(0.6),
                ),
                itemBuilder: (context, index) {
                  final message = widget.messages[index];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.info_outline_rounded),
                    title: SelectableText(message),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
