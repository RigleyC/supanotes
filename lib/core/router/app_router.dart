library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/core/router/last_route_store.dart';
import 'package:supanotes/features/auth/domain/user.dart';

import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/router/auth_guard.dart';
import 'package:supanotes/features/agent/presentation/chat_screen.dart';
import 'package:supanotes/features/auth/presentation/login_screen.dart';
import 'package:supanotes/features/auth/presentation/register_screen.dart';
import 'package:supanotes/features/auth/presentation/splash_screen.dart';
import 'package:supanotes/features/memories/presentation/memories_screen.dart';
import 'package:supanotes/features/notes/presentation/note_editor_screen.dart';
import 'package:supanotes/features/notes/presentation/notes_list_screen.dart';
import 'package:supanotes/features/settings/presentation/contexts_screen.dart';
import 'package:supanotes/features/settings/presentation/mcp_screen.dart';
import 'package:supanotes/features/settings/presentation/settings_screen.dart';
import 'package:supanotes/features/settings/presentation/soul_editor_screen.dart';
import 'package:supanotes/features/routines/presentation/brief_history_screen.dart';
import 'package:supanotes/features/routines/presentation/routines_screen.dart';
import 'package:supanotes/features/telegram/presentation/telegram_link_screen.dart';

final goRouterProvider = Provider<GoRouter>((ref) {
  final notifier = ValueNotifier<AsyncValue<User?>>(
    ref.read(authControllerProvider),
  );
  ref.listen<AsyncValue<User?>>(
    authControllerProvider,
    (_, next) => notifier.value = next,
  );
  ref.onDispose(notifier.dispose);

  final lastRouteStore = ref.watch(lastRouteStoreProvider);

  final router = GoRouter(
    initialLocation: lastRouteStore.initialLocation(),
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
      GoRoute(path: AppRoutes.chat, builder: (_, _) => const ChatScreen()),
      GoRoute(
        path: AppRoutes.note(':id'),
        builder: (_, state) =>
            NoteEditorScreen(noteId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, _) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.soul,
        builder: (_, _) => const SoulEditorScreen(),
      ),
      GoRoute(
        path: AppRoutes.contexts,
        builder: (_, _) => const ContextsScreen(),
      ),
      GoRoute(
        path: AppRoutes.routines,
        builder: (_, _) => const RoutinesScreen(),
      ),
      GoRoute(
        path: AppRoutes.routinesLogs,
        builder: (_, _) => const BriefHistoryScreen(),
      ),
      GoRoute(
        path: AppRoutes.telegram,
        builder: (_, _) => const TelegramLinkScreen(),
      ),
      GoRoute(
        path: AppRoutes.memories,
        builder: (_, _) => const MemoriesScreen(),
      ),
      GoRoute(path: AppRoutes.mcp, builder: (_, _) => const McpScreen()),
    ],
    redirect: (context, state) {
      final result = authGuardRedirect(
        currentLocation: state.matchedLocation,
        authState: notifier.value,
        persistedLocation: lastRouteStore.initialLocation(),
      );
      debugPrint(
        '[LastRoute] redirect result=$result for location=${state.matchedLocation}',
      );
      return result;
    },
  );

  void onRouteChanged() {
    final authState = notifier.value;
    if (authState is! AsyncData<User?>) return;
    if (authState.value == null) return;
    final location = router.routerDelegate.currentConfiguration.uri.toString();
    debugPrint('[LastRoute] onRouteChanged saving: $location');
    unawaited(lastRouteStore.save(location));
  }

  router.routerDelegate.addListener(onRouteChanged);
  ref.onDispose(() => router.routerDelegate.removeListener(onRouteChanged));

  return router;
});
