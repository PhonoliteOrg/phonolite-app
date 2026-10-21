import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:phonolite_app/application/controllers/playlists/playlist_editor_controller.dart';
import 'package:phonolite_app/data/models/playback/playback_state.dart';
import 'package:phonolite_app/ui/controller_binding.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_text_field.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/interaction/button_haptics.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/modal_action_button.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_dialog.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_editor_dialog.dart';
import 'package:phonolite_app/ui/shared/design_system/modals/obsidian_modal_scope.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';
import 'package:phonolite_app/ui/shared/music/artwork/album_art.dart';
import 'package:phonolite_app/ui/shared/music/local_server_toggle.dart';

export 'package:phonolite_app/application/controllers/playlists/playlist_editor_controller.dart'
    show PlaylistEditorSubmit, PlaylistEditorTarget;

class PlaylistEditorModal extends StatefulWidget {
  final String title;
  final String initialValue;
  final String initialDescription;
  final PlaylistEditorSubmit onSubmit;
  final String? initialImageUrl;
  final Map<String, String> imageHeaders;
  final bool showTargetSelector;
  final PlaylistEditorTarget initialTarget;

  const PlaylistEditorModal({
    super.key,
    required this.title,
    required this.initialValue,
    required this.onSubmit,
    this.initialDescription = '',
    this.initialImageUrl,
    this.imageHeaders = const <String, String>{},
    this.showTargetSelector = false,
    this.initialTarget = PlaylistEditorTarget.local,
  });

  @override
  State<PlaylistEditorModal> createState() => _PlaylistEditorModalState();
}

class _PlaylistEditorModalState extends State<PlaylistEditorModal> with ControllerBinding<PlaylistEditorModal> {
  static const int _maxNameLength = PlaylistEditorController.maxNameLength;
  static const int _maxDescriptionLength = PlaylistEditorController.maxDescriptionLength;

  late final PlaylistEditorController _feature = bindController(
    PlaylistEditorController(widget.onSubmit, widget.initialTarget),
  );
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  bool _clamping = false;

  @override
  void initState() {
    super.initState();

    final initial = widget.initialValue.trim();
    final clamped = initial.length > _maxNameLength ? initial.substring(0, _maxNameLength) : initial;

    final initialDescription = widget.initialDescription.trim();
    final clampedDescription = initialDescription.length > _maxDescriptionLength
        ? initialDescription.substring(0, _maxDescriptionLength)
        : initialDescription;

    _nameController = TextEditingController(text: clamped);
    _descriptionController = TextEditingController(text: clampedDescription);

    _nameController.addListener(_handleNameChanged);
    _descriptionController.addListener(_handleDescriptionChanged);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();

    super.dispose();
  }

  void _handleNameChanged() => _handleFieldChanged(_nameController, _maxNameLength);

  void _handleDescriptionChanged() => _handleFieldChanged(_descriptionController, _maxDescriptionLength);

  void _handleFieldChanged(TextEditingController controller, int maxLength) {
    if (_clamping) {
      return;
    }

    final text = controller.text;

    if (text.length > maxLength) {
      _clamping = true;

      final next = text.substring(0, maxLength);
      final cursor = controller.selection.baseOffset;
      final nextCursor = cursor < 0 || cursor > next.length ? next.length : cursor;

      controller.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: nextCursor),
      );

      _clamping = false;
    }

    setState(() {});
  }

  Future<void> _submit() async {
    final saved = await _feature.submit(_nameController.text, _descriptionController.text);

    if (mounted && saved) {
      Navigator.of(context).pop();
    }
  }

  Widget _buildEditor(BuildContext context) {
    final theme = Theme.of(context);
    final rawLength = _nameController.text.length;
    final currentLength = rawLength > _maxNameLength ? _maxNameLength : rawLength;
    final descriptionLength = _descriptionController.text.length > _maxDescriptionLength
        ? _maxDescriptionLength
        : _descriptionController.text.length;
    final canSave = _nameController.text.trim().isNotEmpty && !_feature.saving;

    final dialogWidth = (MediaQuery.of(context).size.width - ObsidianModalScope.insetsOf(context).horizontal)
        .clamp(0.0, 760.0)
        .toDouble();
    final extraTextHeight = (MediaQuery.textScalerOf(context).scale(16) - 16).clamp(0.0, double.infinity);
    final touchLayout = ObsidianModalScope.usesTouchTargets(context);
    final formHeight = (touchLayout ? 320 : 280) + extraTextHeight * (touchLayout ? 8 : 6);
    final nameFieldHeight = (touchLayout ? 56 : 48) + extraTextHeight;
    final compact =
        dialogWidth - ObsidianModalStyle.contentPadding.horizontal < formHeight + 24 + 280 + extraTextHeight * 2;

    final imagePicker = Align(
      alignment: compact ? Alignment.center : Alignment.centerLeft,
      child: _PlaylistImagePicker(
        title: _nameController.text.trim().isEmpty ? 'Playlist' : _nameController.text.trim(),
        imageUrl: widget.initialImageUrl,
        headers: widget.imageHeaders,
        bytes: _feature.selectedImageBytes,
        size: compact ? 180 : formHeight,
        onTap: () => unawaited(_feature.pickImage()),
      ),
    );

    final fields = SizedBox(
      height: formHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showTargetSelector) ...[
            Align(
              alignment: touchLayout ? Alignment.center : Alignment.centerLeft,
              child: LocalServerToggle(
                value: _feature.target == PlaylistEditorTarget.local ? ActionScope.local : ActionScope.server,
                onChanged: (value) => _feature.setTarget(
                  value == ActionScope.local ? PlaylistEditorTarget.local : PlaylistEditorTarget.server,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _PlaylistFieldHeading(label: 'Name', counter: '$currentLength/$_maxNameLength'),
          const SizedBox(height: 6),
          ObsidianTextField(
            controller: _nameController,
            hintText: 'Playlist name',
            height: nameFieldHeight,
            startPadding: 24,
            cut: 0,
            isDense: true,
            maxLines: 1,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
          ),
          const SizedBox(height: 16),
          _PlaylistFieldHeading(label: 'Description', counter: '$descriptionLength/$_maxDescriptionLength'),
          const SizedBox(height: 6),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => ObsidianTextField(
                controller: _descriptionController,
                hintText: 'Playlist description',
                height: constraints.maxHeight,
                startPadding: 24,
                cut: 0,
                minLines: 1,
                maxLines: null,
                textInputAction: TextInputAction.done,
                keyboardType: TextInputType.multiline,
                onSubmitted: (_) => FocusScope.of(context).unfocus(),
              ),
            ),
          ),
        ],
      ),
    );

    final imageError = _feature.imageError == null
        ? null
        : Text(_feature.imageError!, style: theme.textTheme.labelSmall?.copyWith(color: Colors.redAccent));

    final editor = compact
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [imagePicker, const SizedBox(height: 18), fields],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              imagePicker,
              const SizedBox(width: 24),
              Expanded(child: fields),
            ],
          );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        editor,
        if (imageError != null) ...[const SizedBox(height: 10), imageError],
      ],
    );

    return ObsidianEditorDialog(
      title: Text(widget.title),
      width: dialogWidth,
      content: content,
      actions: [
        ModalActionButton(label: 'Close', onPressed: () => Navigator.of(context).pop()),
        ModalActionButton(
          label: _feature.saving ? 'Saving' : 'Save',
          onPressed: canSave ? () => unawaited(_submit()) : null,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ObsidianModalScope(builder: _buildEditor);
}

class _PlaylistImagePicker extends StatelessWidget {
  final String title;
  final String? imageUrl;
  final Map<String, String> headers;
  final Uint8List? bytes;
  final double size;
  final VoidCallback onTap;

  const _PlaylistImagePicker({
    required this.title,
    required this.imageUrl,
    required this.headers,
    required this.bytes,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final imageBytes = bytes;
    final imagePath = imageUrl?.trim();
    final hasImage = imageBytes != null || (imagePath != null && imagePath.isNotEmpty);
    final quietPlaceholder = _QuietPlaylistArtPlaceholder(size: size);
    final Widget art;

    if (imageBytes == null && hasImage) {
      art = AlbumArt(title: title, size: size, imageUrl: imagePath, headers: headers, placeholder: quietPlaceholder);
    } else if (imageBytes == null) {
      art = quietPlaceholder;
    } else {
      art = Image.memory(
        imageBytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => quietPlaceholder,
      );
    }

    return SizedBox(
      width: size,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: 'Choose image',
            preferBelow: true,
            verticalOffset: 10,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: withButtonHaptic(onTap),
                behavior: HitTestBehavior.opaque,
                child: ClipRect(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(width: size, height: size, child: art),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            border: Border.all(color: ObsidianPalette.border),
                          ),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(PhonoliteIcons.imagePlus, color: ObsidianPalette.textMuted, size: 34),
                          const SizedBox(height: 8),
                          Text(
                            'Choose image',
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: ObsidianPalette.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuietPlaylistArtPlaceholder extends StatelessWidget {
  final double size;

  const _QuietPlaylistArtPlaceholder({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(width: size, height: size, color: ObsidianPalette.obsidianGlass.withValues(alpha: 0.5));
  }
}

class _PlaylistFieldHeading extends StatelessWidget {
  final String label;
  final String counter;

  const _PlaylistFieldHeading({required this.label, required this.counter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(color: ObsidianPalette.textMuted, letterSpacing: 1.2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          counter,
          style: theme.textTheme.labelSmall?.copyWith(color: ObsidianPalette.textMuted, letterSpacing: 0.6),
        ),
      ],
    );
  }
}
