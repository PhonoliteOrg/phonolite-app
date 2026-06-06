import 'package:flutter/material.dart';

import '../ui/tech_button.dart';

class ModalActionButton extends StatelessWidget {
  const ModalActionButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.variant = TechButtonVariant.standard,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final TechButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    return TechButton(
      label: label,
      icon: icon,
      density: TechButtonDensity.compact,
      chrome: TechButtonChrome.borderless,
      variant: variant,
      onTap: onPressed,
    );
  }
}
