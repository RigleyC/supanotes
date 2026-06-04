import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'shared/theme/app_theme.dart';
import 'shared/widgets/splash_screen.dart';

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
