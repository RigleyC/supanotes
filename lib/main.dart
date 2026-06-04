import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'shared/theme/app_spacing.dart';
import 'shared/theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: SupaNotesApp()));
}

/// Root widget for the SupaNotes application.
///
/// Currently a [MaterialApp] (not [MaterialApp.router]) because routing is
/// not wired up yet — FE-1 will introduce go_router and switch this to
/// [MaterialApp.router]. For now the home screen is a minimal splash
/// placeholder so the rest of the design system can be exercised
/// end-to-end.
class SupaNotesApp extends StatelessWidget {
  const SupaNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      // Dark mode is the default; FE-12 will wire this to user settings
      // and the system brightness.
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: const SplashScreen(),
    );
  }
}

/// Minimal placeholder shown on first launch.
///
/// This is intentionally bare — it exists so the app has something to
/// render before the router, auth, and home screens land in FE-1 / FE-4.
/// Once the real home screen ships, the splash can be reused as a
/// launch-time interstitial that defers to [SplashScreen.onReady] once
/// bootstrap (Drift open, auth restore, sync kick-off) is complete.
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
