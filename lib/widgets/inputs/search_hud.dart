import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../ui/chamfered.dart';
import '../ui/hoverable.dart';
import 'obsidian_text_field.dart';

class SearchHud extends StatelessWidget {
  const SearchHud({
    super.key,
    required this.controller,
    required this.onSubmit,
    required this.onClear,
    this.onChanged,
    this.hintText = 'Search library',
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final VoidCallback onClear;
  final VoidCallback? onChanged;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final hasText = value.text.trim().isNotEmpty;
        return Row(
          children: [
            Expanded(
              child: ObsidianTextField(
                controller: controller,
                hintText: hintText,
                onSubmitted: (_) => onSubmit(),
                onChanged: (_) => onChanged?.call(),
                textInputAction: TextInputAction.search,
                suffixIcon: hasText
                    ? IconButton(
                        onPressed: () {
                          controller.clear();
                          onClear();
                        },
                        icon: const Icon(Icons.close_rounded),
                        color: Colors.white70,
                        splashRadius: 18,
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            _SearchExecuteButton(onTap: onSubmit),
          ],
        );
      },
    );
  }
}

class _SearchExecuteButton extends StatelessWidget {
  const _SearchExecuteButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ObsidianHoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) {
        final background = hovered ? accentGold : accentGold.withOpacity(0.1);
        final iconColor = hovered ? Colors.black : accentGold;

        return GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: const BoxDecoration(),
            child: ClipPath(
              clipper: CutBottomRightClipper(cut: 15),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: searchHudHeight,
                height: searchHudHeight,
                color: background,
                child: Icon(Icons.search_rounded, color: iconColor),
              ),
            ),
          ),
        );
      },
    );
  }
}
