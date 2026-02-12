import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../entities/app_log.dart';
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

  final List<LogEntry> messages;
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
    final theme = Theme.of(context);
    final defaultSubtitle =
        widget.messages.isEmpty ? 'No events yet' : 'System log';
    final combined = widget.messages.map((entry) => entry.format()).join('\n');
    final canCopy = combined.isNotEmpty;
    final copyButton = TextButton.icon(
      onPressed: canCopy
          ? () async {
              await Clipboard.setData(ClipboardData(text: combined));
              if (!mounted) {
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Copied ${widget.messages.length} log entries'),
                ),
              );
            }
          : null,
      icon: const Icon(Icons.copy_all_rounded),
      label: const Text('Copy All'),
    );
    final clearButton = widget.onClear == null
        ? null
        : TextButton.icon(
            onPressed: widget.onClear,
            icon: const Icon(Icons.clear_all_rounded),
            label: const Text('Clear'),
          );
    final trailing = widget.trailing ??
        Wrap(
          spacing: 8,
          children: [
            copyButton,
            if (clearButton != null) clearButton,
          ],
        );

    final baseStyle = theme.textTheme.bodyMedium?.copyWith(height: 1.4) ??
        const TextStyle(height: 1.4);

    final lineColor = ObsidianPalette.border.withOpacity(0.35);
    final lines = <Widget>[];
    for (var i = 0; i < widget.messages.length; i++) {
      final entry = widget.messages[i];
      final color = _colorForLevel(entry.level, theme);
      lines.add(
        SelectableText(
          '[${entry.timestampLabel}][${entry.levelLabel}] ${entry.message}',
          style: baseStyle.copyWith(color: color),
        ),
      );
      if (i < widget.messages.length - 1) {
        lines.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Container(height: 1, color: lineColor),
          ),
        );
      }
    }

    return Column(
      children: [
        ObsidianSectionHeader(
          title: widget.title,
          subtitle: widget.subtitle ?? defaultSubtitle,
          trailing: trailing,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            color: ObsidianPalette.obsidianGlass,
            child: SelectableRegion(
              focusNode: _selectionFocus,
              selectionControls: materialTextSelectionControls,
              child: widget.messages.isEmpty
                  ? Center(
                      child: Text(
                        'No events yet',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: ObsidianPalette.textMuted,
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: lines,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
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
      default:
        return ObsidianPalette.textPrimary;
    }
  }
}
