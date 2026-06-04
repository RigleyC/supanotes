/// Minimal launch-time interstitial shown while the auth controller
/// resolves the saved session.
///
/// The router uses this at the `/` route so the app always has *something*
/// to render during the brief window between first frame and
/// `AuthController.build()` returning. Once the controller resolves,
/// [GoRouter.redirect] bounces the user to `/login` or `/home` as
/// appropriate and this screen disappears.
library;

import 'package:flutter/material.dart';

import 'package:supanotes/core/constants/app_constants.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppConstants.appName,
              style: textTheme.displaySmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Notes that think ahead.',
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
