import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../modals/obsidian_modal_scope.dart';
import '../ui/blur.dart';
import '../ui/chamfered.dart';
import '../ui/obsidian_theme.dart';

class ObsidianTextField extends StatefulWidget {
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
    this.startPadding = 16,
    this.isDense = false,
    this.cut = 15,
    this.enabled = true,
    this.textInputAction,
    this.keyboardType,
    this.maxLines = 1,
    this.minLines,
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
  final double startPadding;
  final bool isDense;
  final double cut;
  final bool enabled;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;
  final int? maxLines;
  final int? minLines;

  @override
  State<ObsidianTextField> createState() => _ObsidianTextFieldState();
}

class _ObsidianTextFieldState extends State<ObsidianTextField> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final singleLine = widget.maxLines == 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: theme.textTheme.labelLarge?.copyWith(
              color: ObsidianPalette.textMuted,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
        ],
        ClipPath(
          clipper: CutTopLeftClipper(cut: widget.cut),
          child: maybeBlur(
            sigma: 14,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: singleLine && widget.enabled
                  ? _focusNode.requestFocus
                  : null,
              child: Container(
                height: widget.height,
                // Center the decorator itself, not just its inner text.
                alignment: singleLine ? Alignment.center : null,
                padding: EdgeInsetsDirectional.only(
                  start: widget.startPadding,
                  end: 16,
                  top: singleLine || widget.isDense ? 0 : 6,
                  bottom: singleLine || widget.isDense ? 0 : 6,
                ),
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
                  controller: widget.controller,
                  focusNode: _focusNode,
                  obscureText: widget.obscureText,
                  enabled: widget.enabled,
                  keyboardType: widget.keyboardType,
                  textInputAction: widget.textInputAction,
                  textAlignVertical: singleLine || widget.isDense
                      ? TextAlignVertical.center
                      : null,
                  maxLines: widget.maxLines,
                  minLines: widget.minLines,
                  style: GoogleFonts.rajdhani(
                    fontSize: ObsidianModalScope.usesTouchTargets(context)
                        ? 16
                        : null,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0,
                  ),
                  decoration: InputDecoration(
                    // Desktop compact density offsets an empty hint vertically.
                    visualDensity: singleLine ? VisualDensity.standard : null,
                    isDense: singleLine || widget.isDense,
                    contentPadding: singleLine || widget.isDense
                        ? EdgeInsets.zero
                        : null,
                    hintText: widget.hintText,
                    hintStyle: GoogleFonts.rajdhani(
                      fontSize: ObsidianModalScope.usesTouchTargets(context)
                          ? 16
                          : null,
                      color: Colors.white54,
                      letterSpacing: 1.0,
                    ),
                    border: InputBorder.none,
                    prefixIcon: widget.prefixIcon,
                    suffixIcon: widget.suffixIcon,
                  ),
                  onSubmitted: widget.onSubmitted,
                  onChanged: widget.onChanged,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
