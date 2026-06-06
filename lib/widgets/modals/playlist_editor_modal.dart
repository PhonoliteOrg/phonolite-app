import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import '../../entities/models.dart';
import '../display/album_art.dart';
import '../inputs/obsidian_text_field.dart';
import '../ui/obsidian_theme.dart';
import 'modal_action_button.dart';
import 'playlist_image_file_picker.dart';

typedef PlaylistEditorSubmit =
    FutureOr<void> Function(
      String name,
      String description,
      PlaylistImageEdit imageEdit,
      PlaylistEditorTarget target,
    );

enum PlaylistEditorTarget { local, server }

class PlaylistEditorModal extends StatefulWidget {
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

  final String title;
  final String initialValue;
  final String initialDescription;
  final PlaylistEditorSubmit onSubmit;
  final String? initialImageUrl;
  final Map<String, String> imageHeaders;
  final bool showTargetSelector;
  final PlaylistEditorTarget initialTarget;

  @override
  State<PlaylistEditorModal> createState() => _PlaylistEditorModalState();
}

class _PlaylistEditorModalState extends State<PlaylistEditorModal> {
  static const int _maxNameLength = 24;
  static const int _maxDescriptionLength = 500;
  static const int _maxImageBytes = 5 * 1024 * 1024;
  static const List<String> _imageExtensions = <String>[
    'jpg',
    'jpeg',
    'png',
    'webp',
  ];

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  Uint8List? _selectedImageBytes;
  String? _selectedImageContentType;
  String? _imageError;
  late PlaylistEditorTarget _target;
  bool _clamping = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValue.trim();
    final clamped = initial.length > _maxNameLength
        ? initial.substring(0, _maxNameLength)
        : initial;
    final initialDescription = widget.initialDescription.trim();
    final clampedDescription = initialDescription.length > _maxDescriptionLength
        ? initialDescription.substring(0, _maxDescriptionLength)
        : initialDescription;
    _nameController = TextEditingController(text: clamped);
    _descriptionController = TextEditingController(text: clampedDescription);
    _target = widget.initialTarget;
    _nameController.addListener(_handleNameChanged);
    _descriptionController.addListener(_handleDescriptionChanged);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _handleNameChanged() {
    if (_clamping) {
      return;
    }
    final text = _nameController.text;
    if (text.length > _maxNameLength) {
      _clamping = true;
      final next = text.substring(0, _maxNameLength);
      final cursor = _nameController.selection.baseOffset;
      final nextCursor = cursor < 0
          ? next.length
          : (cursor > next.length ? next.length : cursor);
      _nameController.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: nextCursor),
      );
      _clamping = false;
    }
    setState(() {});
  }

  void _handleDescriptionChanged() {
    if (_clamping) {
      return;
    }
    final text = _descriptionController.text;
    if (text.length > _maxDescriptionLength) {
      _clamping = true;
      final next = text.substring(0, _maxDescriptionLength);
      final cursor = _descriptionController.selection.baseOffset;
      final nextCursor = cursor < 0
          ? next.length
          : (cursor > next.length ? next.length : cursor);
      _descriptionController.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: nextCursor),
      );
      _clamping = false;
    }
    setState(() {});
  }

  Future<void> _pickImage() async {
    setState(() => _imageError = null);
    final XFile? file;
    try {
      file = await openPlaylistImageFile(
        acceptedTypeGroups: const <XTypeGroup>[
          XTypeGroup(
            label: 'Images',
            extensions: _imageExtensions,
            mimeTypes: <String>['image/jpeg', 'image/png', 'image/webp'],
          ),
        ],
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _imageError = 'Image picker is unavailable.');
      return;
    }
    if (file == null) {
      return;
    }
    final contentType = _contentTypeForName(file.name);
    if (contentType == 'application/octet-stream') {
      setState(() => _imageError = 'Selected image type is not supported.');
      return;
    }
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _imageError = 'Selected image could not be read.');
      return;
    }
    if (bytes.isEmpty) {
      setState(() => _imageError = 'Selected image is empty.');
      return;
    }
    if (bytes.length > _maxImageBytes) {
      setState(() => _imageError = 'Selected image is too large.');
      return;
    }
    setState(() {
      _selectedImageBytes = bytes;
      _selectedImageContentType = contentType;
    });
  }

  Future<void> _submit() async {
    if (_saving) {
      return;
    }
    var trimmed = _nameController.text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    if (trimmed.length > _maxNameLength) {
      trimmed = trimmed.substring(0, _maxNameLength);
    }
    final description = _descriptionController.text.trim();
    setState(() => _saving = true);
    try {
      await Future<void>.sync(
        () => widget.onSubmit(trimmed, description, _imageEdit, _target),
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (err) {
      if (mounted) {
        setState(() {
          _saving = false;
          _imageError = 'Failed to save playlist.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rawLength = _nameController.text.length;
    final currentLength = rawLength > _maxNameLength
        ? _maxNameLength
        : rawLength;
    final descriptionLength =
        _descriptionController.text.length > _maxDescriptionLength
        ? _maxDescriptionLength
        : _descriptionController.text.length;
    final canSave = _nameController.text.trim().isNotEmpty && !_saving;
    final dialogWidth = (MediaQuery.of(context).size.width - 48)
        .clamp(0.0, 760.0)
        .toDouble();
    final compact = dialogWidth < 620;
    final imagePicker = Align(
      alignment: compact ? Alignment.center : Alignment.centerLeft,
      child: _PlaylistImagePicker(
        title: _nameController.text.trim().isEmpty
            ? 'Playlist'
            : _nameController.text.trim(),
        imageUrl: widget.initialImageUrl,
        headers: widget.imageHeaders,
        bytes: _selectedImageBytes,
        size: compact ? 180 : 214,
        onTap: () => unawaited(_pickImage()),
      ),
    );
    final fields = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ObsidianTextField(
          controller: _nameController,
          label: 'Name',
          hintText: 'Playlist name',
          maxLines: 1,
          textInputAction: TextInputAction.next,
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
        const SizedBox(height: 12),
        ObsidianTextField(
          controller: _descriptionController,
          label: 'Description',
          hintText: 'Playlist summary',
          height: 132,
          minLines: 4,
          maxLines: 4,
          textInputAction: TextInputAction.newline,
          keyboardType: TextInputType.multiline,
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '$descriptionLength/$_maxDescriptionLength',
            style: theme.textTheme.labelSmall?.copyWith(
              color: ObsidianPalette.textMuted,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ],
    );
    final imageError = _imageError == null
        ? null
        : Text(
            _imageError!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.redAccent,
            ),
          );
    final content = compact
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              imagePicker,
              const SizedBox(height: 18),
              fields,
              if (imageError != null) ...[
                const SizedBox(height: 10),
                imageError,
              ],
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              imagePicker,
              const SizedBox(width: 24),
              Expanded(child: fields),
              if (imageError != null) ...[
                const SizedBox(width: 14),
                SizedBox(width: 160, child: imageError),
              ],
            ],
          );
    final targetSelector = !widget.showTargetSelector
        ? null
        : Align(
            alignment: compact ? Alignment.centerLeft : Alignment.centerRight,
            child: _PlaylistTargetToggle(
              value: _target,
              onChanged: (value) => setState(() => _target = value),
            ),
          );
    final maxDialogHeight = (MediaQuery.of(context).size.height - 48)
        .clamp(0.0, double.infinity)
        .toDouble();
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxDialogHeight),
        child: SizedBox(
          width: dialogWidth,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(widget.title)),
                    IconButton(
                      tooltip: 'Close',
                      constraints: const BoxConstraints.tightFor(
                        width: 36,
                        height: 36,
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                if (targetSelector != null) ...[
                  targetSelector,
                  const SizedBox(height: 8),
                ],
                Flexible(
                  fit: FlexFit.loose,
                  child: SingleChildScrollView(child: content),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: ModalActionButton(
                    label: _saving ? 'Saving' : 'Save',
                    onPressed: canSave ? () => unawaited(_submit()) : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PlaylistImageEdit get _imageEdit {
    final bytes = _selectedImageBytes;
    if (bytes != null) {
      return PlaylistImageEdit.replace(
        bytes: bytes,
        contentType: _selectedImageContentType ?? 'application/octet-stream',
      );
    }
    return const PlaylistImageEdit.keep();
  }

  String _contentTypeForName(String name) {
    final lower = name.trim().toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'application/octet-stream';
  }
}

class _PlaylistImagePicker extends StatelessWidget {
  const _PlaylistImagePicker({
    required this.title,
    required this.imageUrl,
    required this.headers,
    required this.bytes,
    required this.size,
    required this.onTap,
  });

  final String title;
  final String? imageUrl;
  final Map<String, String> headers;
  final Uint8List? bytes;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final imageBytes = bytes;
    final imagePath = imageUrl?.trim();
    final hasImage =
        imageBytes != null || (imagePath != null && imagePath.isNotEmpty);
    final quietPlaceholder = _QuietPlaylistArtPlaceholder(size: size);
    final art = imageBytes == null && hasImage
        ? AlbumArt(
            title: title,
            size: size,
            imageUrl: imagePath,
            headers: headers,
            placeholder: quietPlaceholder,
          )
        : imageBytes == null
        ? quietPlaceholder
        : Image.memory(
            imageBytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => quietPlaceholder,
          );
    return SizedBox(
      width: size,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: hasImage ? 'Change image' : 'Choose image',
            preferBelow: true,
            verticalOffset: 10,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onTap,
                behavior: HitTestBehavior.opaque,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(width: size, height: size, child: art),
                      if (!hasImage) ...[
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.transparent,
                              border: Border.all(color: ObsidianPalette.border),
                            ),
                          ),
                        ),
                        Icon(
                          Icons.add_photo_alternate_outlined,
                          color: ObsidianPalette.textMuted,
                          size: 34,
                        ),
                      ],
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
  const _QuietPlaylistArtPlaceholder({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      color: ObsidianPalette.obsidianGlass.withValues(alpha: 0.5),
    );
  }
}

class _PlaylistTargetToggle extends StatelessWidget {
  const _PlaylistTargetToggle({required this.value, required this.onChanged});

  static const double _height = 36;

  final PlaylistEditorTarget value;
  final ValueChanged<PlaylistEditorTarget> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PlaylistTargetOption(
            label: 'LOCAL',
            selected: value == PlaylistEditorTarget.local,
            onTap: () => onChanged(PlaylistEditorTarget.local),
            height: _height,
          ),
          const SizedBox(width: 8),
          _PlaylistTargetOption(
            label: 'SERVER',
            selected: value == PlaylistEditorTarget.server,
            onTap: () => onChanged(PlaylistEditorTarget.server),
            height: _height,
          ),
        ],
      ),
    );
  }
}

class _PlaylistTargetOption extends StatefulWidget {
  const _PlaylistTargetOption({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.height,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double height;

  @override
  State<_PlaylistTargetOption> createState() => _PlaylistTargetOptionState();
}

class _PlaylistTargetOptionState extends State<_PlaylistTargetOption> {
  static const _transition = Duration(milliseconds: 160);
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) {
      return;
    }
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final highlighted = widget.selected || _hovered;
    final borderColor = highlighted
        ? ObsidianPalette.gold.withValues(alpha: 0.6)
        : Colors.white.withValues(alpha: 0.12);
    final textColor = highlighted
        ? ObsidianPalette.gold
        : ObsidianPalette.textMuted;

    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: _transition,
          curve: Curves.easeOut,
          alignment: Alignment.center,
          constraints: BoxConstraints(minHeight: widget.height),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            border: Border.all(color: borderColor),
            boxShadow: [
              if (highlighted)
                BoxShadow(
                  color: ObsidianPalette.gold.withValues(alpha: 0.35),
                  blurRadius: 10,
                ),
            ],
          ),
          child: AnimatedDefaultTextStyle(
            duration: _transition,
            curve: Curves.easeOut,
            style:
                Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: textColor,
                  letterSpacing: 1.0,
                ) ??
                TextStyle(color: textColor),
            child: Text(widget.label),
          ),
        ),
      ),
    );
  }
}
