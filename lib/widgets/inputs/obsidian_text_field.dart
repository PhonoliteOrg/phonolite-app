import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../ui/blur.dart';
import '../ui/chamfered.dart';
import '../ui/obsidian_theme.dart';

class ObsidianTextField extends StatelessWidget {
  const ObsidianTextField({
    super.key,
    required this.controller,
    this.label,
    this.hintText,
    this.obscureText = false,
    this.prefixIcon,
    this.suffixIcon,
    this.onSubmitted,
    this.onChanged,
    this.height = searchHudHeight,
    this.cut = 15,
    this.enabled = true,
    this.textInputAction,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String? label;
  final String? hintText;
  final bool obscureText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final double height;
  final double cut;
  final bool enabled;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: theme.textTheme.labelLarge?.copyWith(
              color: ObsidianPalette.textMuted,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
        ],
        ClipPath(
          clipper: CutTopLeftClipper(cut: cut),
          child: maybeBlur(
            sigma: 14,
            child: Container(
              height: height,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.05),
                    Colors.white.withOpacity(0.01),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withOpacity(0.18),
                    width: 1,
                  ),
                ),
              ),
              child: TextField(
                controller: controller,
                obscureText: obscureText,
                enabled: enabled,
                keyboardType: keyboardType,
                textInputAction: textInputAction,
                style: GoogleFonts.rajdhani(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                ),
                decoration: InputDecoration(
                  hintText: hintText,
                  hintStyle: GoogleFonts.rajdhani(
                    color: Colors.white54,
                    letterSpacing: 1.0,
                  ),
                  border: InputBorder.none,
                  prefixIcon: prefixIcon,
                  suffixIcon: suffixIcon,
                ),
                onSubmitted: onSubmitted,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
