import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'shared/theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: SupaNotesApp()));
}

/// Root widget for the SupaNotes application.
///
/// Wires the [goRouterProvider] (which already encodes the auth-guard
/// redirect) into [MaterialApp.router] so the rest of the app can be
/// expressed as ordinary widgets and the router can re-evaluate the
/// redirect every time the auth state changes.
class SupaNotesApp extends ConsumerWidget {
  const SupaNotesApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      // Dark mode is the default; FE-12 will wire this to user settings
      // and the system brightness.
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
