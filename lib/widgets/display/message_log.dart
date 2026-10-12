import 'package:flutter/material.dart';

import '../ui/phonolite_icons.dart';
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
    final defaultSubtitle = widget.messages.isEmpty
        ? 'No events yet'
        : 'System log';
    final canCopy = widget.messages.isNotEmpty;
    final copyButton = TextButton.icon(
      onPressed: canCopy
          ? () async {
              // Formatting the entire history is only needed on demand.
              final combined = widget.messages.reversed
                  .map((entry) => entry.format())
                  .join('\n');
              await Clipboard.setData(ClipboardData(text: combined));
            }
          : null,
      icon: const Icon(PhonoliteIcons.copyCheck),
      label: const Text('Copy All'),
    );
    final clearButton = widget.onClear == null
        ? null
        : TextButton.icon(
            onPressed: widget.onClear,
            icon: const Icon(PhonoliteIcons.listX),
            label: const Text('Clear'),
          );
    final trailing =
        widget.trailing ??
        Wrap(
          spacing: 8,
          children: [copyButton, if (clearButton != null) clearButton],
        );

    final baseStyle =
        theme.textTheme.bodyMedium?.copyWith(height: 1.4) ??
        const TextStyle(height: 1.4);

    final lineColor = ObsidianPalette.border.withValues(alpha: 0.35);
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
                  : ListView.separated(
                      itemCount: widget.messages.length,
                      itemBuilder: (context, index) {
                        final entry =
                            widget.messages[widget.messages.length - index - 1];
                        return SelectableText(
                          entry.format(),
                          style: baseStyle.copyWith(
                            color: _colorForLevel(entry.level, theme),
                          ),
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
}
