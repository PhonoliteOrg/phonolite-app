import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_hud_icon_button.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/obsidian_text_field.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/constants.dart';

class SearchHud extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSubmit;
  final VoidCallback onClear;
  final VoidCallback? onChanged;
  final String hintText;
  final double height;

  const SearchHud({
    super.key,
    required this.controller,
    required this.onSubmit,
    required this.onClear,
    this.hintText = 'Search library',
    this.height = searchHudHeight,
    this.onChanged,
  });

  void _clearSearch() {
    controller.clear();
    onClear();
  }

  Widget _clearButton() => Tooltip(
    message: 'Clear search',
    excludeFromSemantics: true,
    child: Semantics(
      button: true,
      label: 'Clear search',
      child: ObsidianHudIconButton(icon: PhonoliteIcons.x, size: 24, onPressed: _clearSearch),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final hasText = value.text.trim().isNotEmpty;

        return ObsidianTextField(
          controller: controller,
          height: height,
          startPadding: 24,
          cut: 0,
          isDense: height < searchHudHeight,
          hintText: hintText,
          onSubmitted: (_) => onSubmit(),
          onChanged: (_) => onChanged?.call(),
          textInputAction: TextInputAction.search,
          suffixIcon: hasText ? _clearButton() : null,
        );
      },
    );
  }
}
