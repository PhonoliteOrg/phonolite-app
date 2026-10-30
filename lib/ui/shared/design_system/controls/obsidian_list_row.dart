import 'package:flutter/material.dart';

import 'package:phonolite_app/ui/shared/design_system/interaction/hover_row.dart';
import 'package:phonolite_app/ui/shared/design_system/layout/responsive_breakpoints.dart';
import 'package:phonolite_app/ui/shared/design_system/theme/obsidian_theme.dart';

/// The responsive frame shared by catalog, search and settings rows.
///
/// Consumers supply their leading presentation and actions; this component owns
/// the common hover surface, spacing and label typography.
class ObsidianListRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isActive;
  final bool enabled;
  final bool canRequestFocus;
  final bool showHover;
  final double? leadingGap;
  final double trailingGap;
  final Color? titleColor;
  final Color subtitleColor;
  final double opacity;

  const ObsidianListRow({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.isActive = false,
    this.enabled = true,
    this.canRequestFocus = true,
    this.showHover = true,
    this.leadingGap,
    this.trailingGap = 0,
    this.titleColor,
    this.subtitleColor = ObsidianPalette.textMuted,
    this.opacity = 1,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final compact = isCompactListWidth(context);

    return ObsidianHoverRow(
      onTap: onTap,
      onLongPress: onLongPress,
      isActive: isActive,
      enabled: enabled,
      canRequestFocus: canRequestFocus,
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      borderColor: showHover ? ObsidianPalette.gold : Colors.transparent,
      hoverGradient: showHover ? null : const LinearGradient(colors: [Colors.transparent, Colors.transparent]),
      hoverColor: showHover ? null : Colors.transparent,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: opacity,
        child: Row(
          children: [
            leading,
            SizedBox(width: leadingGap ?? (compact ? 10 : 14)),
            Expanded(
              child: ObsidianRowLabels(
                title: title,
                subtitle: subtitle,
                titleColor: titleColor,
                subtitleColor: subtitleColor,
              ),
            ),
            if (trailingGap > 0) SizedBox(width: trailingGap),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class ObsidianRowLabels extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Color? titleColor;
  final Color subtitleColor;

  const ObsidianRowLabels({
    super.key,
    required this.title,
    this.subtitle,
    this.titleColor,
    this.subtitleColor = ObsidianPalette.textMuted,
  });

  @override
  Widget build(BuildContext context) {
    final compact = isCompactListWidth(context);
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.titleMedium?.copyWith(
            fontSize: compact ? 14.5 : null,
            letterSpacing: compact ? 0.2 : 0.6,
            color: titleColor,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(
              fontSize: compact ? 12 : null,
              letterSpacing: compact ? 0 : null,
              color: subtitleColor,
            ),
          ),
        ],
      ],
    );
  }
}
