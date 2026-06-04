/// Styled [TextFormField] used by the auth screens.
///
/// Picks up the design system's [InputDecorationTheme] (filled, rounded,
/// no border) and only adds the bits specific to the auth flow: a
/// leading icon and a visible-obscure toggle for the password field.
///
/// All other field-level concerns — controller, focus, autovalidation
/// mode — are owned by the parent screen so this widget stays purely
/// presentational.
library;

import 'package:flutter/material.dart';

import 'package:supanotes/shared/theme/app_spacing.dart';

class AuthFormField extends StatelessWidget {
  const AuthFormField({
    super.key,
    required this.label,
    this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.controller,
    this.textInputAction,
    this.onFieldSubmitted,
    this.autofillHints,
    this.prefixIcon,
    this.suffixIcon,
    this.enabled = true,
  });

  final String label;
  final String? hint;
  final bool obscureText;
  final TextInputType? keyboardType;
  final FormFieldValidator<String>? validator;
  final TextEditingController? controller;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final Iterable<String>? autofillHints;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        validator: validator,
        textInputAction: textInputAction,
        onFieldSubmitted: onFieldSubmitted,
        autofillHints: autofillHints,
        enabled: enabled,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: prefixIcon,
          suffixIcon: suffixIcon,
        ),
      ),
    );
  }
}
