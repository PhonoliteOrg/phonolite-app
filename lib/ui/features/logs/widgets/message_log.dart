import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:phonolite_app/data/models/diagnostics/log_entry.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/button_haptics.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/obsidian_section_header.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

class MessageLog extends StatefulWidget {
  final List<LogEntry> messages;
  final VoidCallback? onClear;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const MessageLog({
    super.key,
    required this.messages,
    this.title = 'Messages',
    this.subtitle,
    this.trailing,
    this.onClear,
  });

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

  Color _colorForLevel(LogLevel level, ThemeData theme) {
    switch (level) {
      case LogLevel.status:
        return ObsidianPalette.gold;
      case LogLevel.warning:
        return Colors.orangeAccent;
      case LogLevel.error:
        return theme.colorScheme.error;
      case LogLevel.debug:
        return ObsidianPalette.textMuted;
      case LogLevel.info:
        return ObsidianPalette.textPrimary;
    }
  }

  Future<void> _copyMessages() async {
    // Formatting the entire history is only needed on demand.
    final combined = widget.messages.reversed.map((entry) => entry.format()).join('\n');

    await Clipboard.setData(ClipboardData(text: combined));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canCopy = widget.messages.isNotEmpty;

    final copyButton = TextButton.icon(
      onPressed: withButtonHaptic(canCopy ? _copyMessages : null),
      icon: const Icon(PhonoliteIcons.copyCheck),
      label: const Text('Copy All'),
    );

    final clearButton = widget.onClear == null
        ? null
        : TextButton.icon(
            onPressed: withButtonHaptic(widget.onClear),
            icon: const Icon(PhonoliteIcons.listX),
            label: const Text('Clear'),
          );

    final trailing = widget.trailing ?? Wrap(spacing: 8, children: [copyButton, if (clearButton != null) clearButton]);

    final baseStyle = theme.textTheme.bodyMedium?.copyWith(height: 1.4) ?? const TextStyle(height: 1.4);

    final lineColor = ObsidianPalette.border.withValues(alpha: 0.35);

    return Column(
      children: [
        ObsidianSectionHeader(title: widget.title, subtitle: widget.subtitle, trailing: trailing),
        const SizedBox(height: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableRegion(
              focusNode: _selectionFocus,
              selectionControls: materialTextSelectionControls,
              child: widget.messages.isEmpty
                  ? Center(
                      child: Text(
                        'No events yet',
                        style: theme.textTheme.bodyMedium?.copyWith(color: ObsidianPalette.textMuted),
                      ),
                    )
                  : ListView.separated(
                      itemCount: widget.messages.length,
                      itemBuilder: (context, index) {
                        final entry = widget.messages[widget.messages.length - index - 1];

                        return SelectableText(
                          entry.format(),
                          style: baseStyle.copyWith(color: _colorForLevel(entry.level, theme)),
                        );
                      },
                      separatorBuilder: (_, __) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Container(height: 1, color: lineColor),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
