/// Primary button used by the auth screens.
///
/// Wraps an [ElevatedButton] with a built-in loading state: when
/// [isLoading] is `true` the label is replaced by a small
/// [CircularProgressIndicator] and the button is disabled so the user
/// can't fire a second request by tapping it twice.
library;

import 'package:flutter/material.dart';

import 'package:supanotes/shared/theme/app_spacing.dart';

class AuthButton extends StatelessWidget {
  const AuthButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: AppSpacing.xl + AppSpacing.md, // 48 logical pixels
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        child: isLoading
            ? const SizedBox(
                width: AppSpacing.md + AppSpacing.xs,
                height: AppSpacing.md + AppSpacing.xs,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(label),
      ),
    );
  }
}
