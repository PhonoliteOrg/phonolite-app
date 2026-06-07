import 'package:flutter/material.dart';

import 'command_link_button.dart';

class DetailActionHeader extends StatelessWidget {
  const DetailActionHeader({
    super.key,
    required this.backLabel,
    required this.onBack,
    required this.actions,
  });

  final String backLabel;
  final VoidCallback onBack;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final backButton = CommandLinkButton(label: backLabel, onTap: onBack);
        final constrainedActions = ConstrainedBox(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth),
          child: actions,
        );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            backButton,
            const SizedBox(width: 12),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: constrainedActions,
              ),
            ),
          ],
        );
      },
    );
  }
}
