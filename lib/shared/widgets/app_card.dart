import 'package:flutter/material.dart';

import 'package:supanotes/shared/theme/app_spacing.dart';

/// Shared surface for grouped feature content.
///
/// Keeping the surface in one component lets feature widgets compose cards
/// without coupling themselves to the app theme's elevation and spacing.
class AppCard extends StatelessWidget {
  const AppCard({required this.child, super.key, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding ?? const EdgeInsets.all(AppSpacing.sm),
        child: child,
      ),
    );
  }
}
