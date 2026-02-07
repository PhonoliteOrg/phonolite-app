import 'package:flutter/material.dart';

import '../inputs/obsidian_text_field.dart';

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
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ObsidianTextField(
              controller: _controller,
              label: 'Name',
              hintText: 'Playlist name',
            ),
            const SizedBox(height: 14),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_controller.text.trim().isEmpty) {
              return;
            }
            widget.onSubmit(_controller.text.trim());
            Navigator.of(context).pop();
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
