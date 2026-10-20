import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../ui/phonolite_icons.dart';
import 'package:file_selector/file_selector.dart';

import '../../entities/models.dart';
import '../display/album_art.dart';
import '../inputs/obsidian_text_field.dart';
import '../ui/obsidian_theme.dart';
import '../../entities/playback_state.dart';
import '../inputs/local_server_toggle.dart';
import 'modal_action_button.dart';
import 'obsidian_dialog.dart';
import 'obsidian_modal_scope.dart';
import 'playlist_image_file_picker.dart';
import '../ui/button_haptics.dart';

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
  static const int _maxNameLength = 32;
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
    final contentType = _contentTypeForFile(file, bytes);
    if (contentType == 'application/octet-stream') {
      setState(() => _imageError = 'Selected image type is not supported.');
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
  Widget build(BuildContext context) =>
      ObsidianModalScope(builder: _buildEditor);

  Widget _buildEditor(BuildContext context) {
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
    final dialogWidth =
        (MediaQuery.of(context).size.width -
                ObsidianModalScope.insetsOf(context).horizontal)
            .clamp(0.0, 760.0)
            .toDouble();
    final extraTextHeight = (MediaQuery.textScalerOf(context).scale(16) - 16)
        .clamp(0.0, double.infinity);
    final touchLayout = ObsidianModalScope.usesTouchTargets(context);
    final formHeight =
        (touchLayout ? 320 : 280) + extraTextHeight * (touchLayout ? 8 : 6);
    final nameFieldHeight = (touchLayout ? 56 : 48) + extraTextHeight;
    final compact =
        dialogWidth - ObsidianModalStyle.contentPadding.horizontal <
        formHeight + 24 + 280 + extraTextHeight * 2;
    final imagePicker = Align(
      alignment: compact ? Alignment.center : Alignment.centerLeft,
      child: _PlaylistImagePicker(
        title: _nameController.text.trim().isEmpty
            ? 'Playlist'
            : _nameController.text.trim(),
        imageUrl: widget.initialImageUrl,
        headers: widget.imageHeaders,
        bytes: _selectedImageBytes,
        size: compact ? 180 : formHeight,
        onTap: () => unawaited(_pickImage()),
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
                value: _target == PlaylistEditorTarget.local
                    ? ActionScope.local
                    : ActionScope.server,
                onChanged: (value) => setState(
                  () => _target = value == ActionScope.local
                      ? PlaylistEditorTarget.local
                      : PlaylistEditorTarget.server,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _PlaylistFieldHeading(
            label: 'Name',
            counter: '$currentLength/$_maxNameLength',
          ),
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
          _PlaylistFieldHeading(
            label: 'Description',
            counter: '$descriptionLength/$_maxDescriptionLength',
          ),
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
    final imageError = _imageError == null
        ? null
        : Text(
            _imageError!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.redAccent,
            ),
          );
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
    final maxDialogHeight =
        (MediaQuery.of(context).size.height -
                ObsidianModalScope.insetsOf(context).vertical -
                MediaQuery.viewInsetsOf(context).vertical -
                MediaQuery.paddingOf(context).vertical)
            .clamp(0.0, double.infinity)
            .toDouble();
    return ObsidianDialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxDialogHeight),
        child: SizedBox(
          width: dialogWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: ObsidianModalStyle.titlePadding,
                child: Text(
                  widget.title,
                  style: ObsidianModalStyle.titleStyle(context),
                ),
              ),
              Flexible(
                fit: FlexFit.loose,
                child: SingleChildScrollView(
                  child: Padding(
                    padding: ObsidianModalStyle.contentPadding,
                    child: DefaultTextStyle.merge(
                      style: ObsidianModalStyle.bodyStyle(context),
                      child: content,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: ObsidianModalStyle.actionsPadding,
                child: ObsidianModalActions(
                  children: [
                    ModalActionButton(
                      label: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    ModalActionButton(
                      label: _saving ? 'Saving' : 'Save',
                      onPressed: canSave ? () => unawaited(_submit()) : null,
                    ),
                  ],
                ),
              ),
            ],
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

  String _contentTypeForFile(XFile file, Uint8List bytes) {
    final mimeType = file.mimeType?.split(';').first.trim().toLowerCase();
    if (mimeType == 'image/jpeg' ||
        mimeType == 'image/jpg' ||
        mimeType == 'image/png' ||
        mimeType == 'image/webp') {
      return mimeType == 'image/jpg' ? 'image/jpeg' : mimeType!;
    }
    final nameType = _contentTypeForName(file.name);
    if (nameType != 'application/octet-stream') {
      return nameType;
    }
    return _contentTypeForBytes(bytes);
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

  String _contentTypeForBytes(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
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
                          const Icon(
                            PhonoliteIcons.imagePlus,
                            color: ObsidianPalette.textMuted,
                            size: 34,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Choose image',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
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

class _PlaylistFieldHeading extends StatelessWidget {
  const _PlaylistFieldHeading({required this.label, required this.counter});

  final String label;
  final String counter;

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
            style: theme.textTheme.labelLarge?.copyWith(
              color: ObsidianPalette.textMuted,
              letterSpacing: 1.2,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          counter,
          style: theme.textTheme.labelSmall?.copyWith(
            color: ObsidianPalette.textMuted,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}
