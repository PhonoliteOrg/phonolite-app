import 'package:flutter/foundation.dart' show nonVirtual;
import 'package:flutter/material.dart';

/// Page-local leading, title and action slots. Route choices belong to pages.
/// This can stay in scroll content or occupy a page's fixed navbar slot.
abstract class BasePageToolbar extends StatelessWidget implements PreferredSizeWidget {
  const BasePageToolbar({super.key});

  @protected
  bool get expandsActions => false;

  @protected
  double get toolbarHeight => 56;

  @override
  Size get preferredSize => Size.fromHeight(toolbarHeight);

  @protected
  Widget? leadingContent(BuildContext context, BoxConstraints constraints) => null;

  @protected
  Widget? titleContent(BuildContext context, BoxConstraints constraints) => null;

  @protected
  Widget? trailingActions(BuildContext context, BoxConstraints constraints) => null;

  @protected
  double contentSpacing(BuildContext context, BoxConstraints constraints) => 12;

  @protected
  CrossAxisAlignment contentAlignment(BuildContext context, BoxConstraints constraints) => CrossAxisAlignment.center;

  @protected
  BoxConstraints? contentConstraints(BuildContext context, BoxConstraints constraints) => null;

  @override
  @nonVirtual
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final leading = leadingContent(context, constraints);
      final title = titleContent(context, constraints);
      final actions = trailingActions(context, constraints);
      final spacing = contentSpacing(context, constraints);

      final row = Row(
        crossAxisAlignment: contentAlignment(context, constraints),
        children: [
          if (leading != null)
            if (title == null && actions == null) Flexible(child: leading) else leading,
          if (title != null) ...[if (leading != null) SizedBox(width: spacing), Expanded(child: title)],
          if (actions != null) ...[
            if (leading != null || title != null) SizedBox(width: spacing),
            if (expandsActions) Expanded(child: actions) else actions,
          ],
        ],
      );

      final bounds = contentConstraints(context, constraints);

      return bounds == null ? row : ConstrainedBox(constraints: bounds, child: row);
    },
  );
}

/// A configurable toolbar for page-specific content without a new subtype.
class PageToolbar extends BasePageToolbar {
  final Widget title;
  final Widget? leading;
  final Widget? actions;

  const PageToolbar({super.key, required this.title, this.leading, this.actions});

  @override
  Widget? leadingContent(BuildContext context, BoxConstraints constraints) => leading;

  @override
  Widget titleContent(BuildContext context, BoxConstraints constraints) => title;

  @override
  Widget? trailingActions(BuildContext context, BoxConstraints constraints) => actions;
}
