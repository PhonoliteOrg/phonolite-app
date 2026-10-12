import 'package:flutter/material.dart';

import '../ui/obsidian_widgets.dart';
import '../ui/phonolite_icons.dart';
import '../../core/constants.dart';
import 'obsidian_text_field.dart';

class SearchHud extends StatelessWidget {
  const SearchHud({
    super.key,
    required this.controller,
    required this.onSubmit,
    required this.onClear,
    this.onChanged,
    this.hintText = 'Search library',
    this.height = searchHudHeight,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final VoidCallback onClear;
  final VoidCallback? onChanged;
  final String hintText;
  final double height;

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
          suffixIcon: hasText
              ? Tooltip(
                  message: 'Clear search',
                  excludeFromSemantics: true,
                  child: Semantics(
                    button: true,
                    label: 'Clear search',
                    child: ObsidianHudIconButton(
                      icon: PhonoliteIcons.x,
                      size: 24,
                      onPressed: () {
                        controller.clear();
                        onClear();
                      },
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }
}
