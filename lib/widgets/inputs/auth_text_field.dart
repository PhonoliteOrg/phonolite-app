import 'package:flutter/material.dart';

import 'obsidian_text_field.dart';

class AuthTextField extends StatelessWidget {
  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hintText,
    this.obscureText = false,
  });

  final TextEditingController controller;
  final String label;
  final String? hintText;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return ObsidianTextField(
      controller: controller,
      label: label,
      hintText: hintText,
      obscureText: obscureText,
    );
  }
}
