import 'package:flutter/material.dart';

import '../inputs/obsidian_text_field.dart';
import '../ui/obsidian_theme.dart';
import '../ui/tech_button.dart';

class PlaylistEditorModal extends StatefulWidget {
  const PlaylistEditorModal({
    super.key,
    required this.title,
    required this.initialValue,
    required this.onSubmit,
  });

  final String title;
  final String initialValue;
  final ValueChanged<String> onSubmit;

  @override
  State<PlaylistEditorModal> createState() => _PlaylistEditorModalState();
}

class _PlaylistEditorModalState extends State<PlaylistEditorModal> {
  static const int _maxNameLength = 24;

  late final TextEditingController _controller;
  bool _clamping = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValue.trim();
    final clamped = initial.length > _maxNameLength
        ? initial.substring(0, _maxNameLength)
        : initial;
    _controller = TextEditingController(text: clamped);
    _controller.addListener(_handleTextChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTextChanged() {
    if (_clamping) {
      return;
    }
    final text = _controller.text;
    if (text.length > _maxNameLength) {
      _clamping = true;
      final next = text.substring(0, _maxNameLength);
      final cursor = _controller.selection.baseOffset;
      final nextCursor =
          cursor < 0 ? next.length : (cursor > next.length ? next.length : cursor);
      _controller.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: nextCursor),
      );
      _clamping = false;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rawLength = _controller.text.length;
    final currentLength =
        rawLength > _maxNameLength ? _maxNameLength : rawLength;
    final canSave = _controller.text.trim().isNotEmpty;
    final dialogWidth =
        (MediaQuery.of(context).size.width - 48).clamp(0.0, 420.0).toDouble();
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      title: Text(widget.title),
      content: SizedBox(
        width: dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ObsidianTextField(
              controller: _controller,
              label: 'Name',
              hintText: 'Playlist name',
              maxLines: 1,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '$currentLength/$_maxNameLength',
                style: theme.textTheme.labelSmall?.copyWith(
                      color: ObsidianPalette.textMuted,
                      letterSpacing: 0.6,
                    ),
              ),
            ),
            const SizedBox(height: 14),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        TechButton(
          label: 'Save',
          density: TechButtonDensity.compact,
          onTap: canSave
              ? () {
                  var trimmed = _controller.text.trim();
                  if (trimmed.isEmpty) {
                    return;
                  }
                  if (trimmed.length > _maxNameLength) {
                    trimmed = trimmed.substring(0, _maxNameLength);
                  }
                  widget.onSubmit(trimmed);
                  Navigator.of(context).pop();
                }
              : null,
        ),
      ],
    );
  }
}
