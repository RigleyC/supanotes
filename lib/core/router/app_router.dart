library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/auth/domain/user.dart';

import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/router/auth_guard.dart';
import 'package:supanotes/features/auth/presentation/login_screen.dart';
import 'package:supanotes/features/auth/presentation/register_screen.dart';
import 'package:supanotes/features/auth/presentation/splash_screen.dart';
import 'package:supanotes/features/notes/presentation/note_editor_screen.dart';
import 'package:supanotes/features/notes/presentation/notes_list_screen.dart';
import 'package:supanotes/features/settings/presentation/mcp_screen.dart';
import 'package:supanotes/features/settings/presentation/settings_screen.dart';

final goRouterProvider = Provider<GoRouter>((ref) {
  final notifier = ValueNotifier<AsyncValue<User?>>(
    ref.read(authControllerProvider),
  );
  ref.listen<AsyncValue<User?>>(
    authControllerProvider,
    (_, next) => notifier.value = next,
  );
  ref.onDispose(notifier.dispose);

  final router = GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,
    refreshListenable: notifier,
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: AppRoutes.register,
        builder: (_, _) => const RegisterScreen(),
      ),
      GoRoute(path: AppRoutes.home, builder: (_, _) => const NotesListScreen()),
      GoRoute(
        path: AppRoutes.note(':id'),
        builder: (_, state) =>
            NoteEditorScreen(noteId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, _) => const SettingsScreen(),
      ),
      GoRoute(path: AppRoutes.mcp, builder: (_, _) => const McpScreen()),
    ],
    redirect: (context, state) {
      final result = authGuardRedirect(
        currentLocation: state.matchedLocation,
        authState: notifier.value,
      );
      return result;
    },
  );

  return router;
});
