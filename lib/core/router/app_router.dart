library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/auth/domain/user.dart';

import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/router/auth_guard.dart';
import 'package:supanotes/features/agent/presentation/chat_screen.dart';
import 'package:supanotes/features/auth/presentation/login_screen.dart';
import 'package:supanotes/features/auth/presentation/register_screen.dart';
import 'package:supanotes/features/notes/presentation/inbox_screen.dart';
import 'package:supanotes/features/notes/presentation/note_editor_screen.dart';
import 'package:supanotes/features/notes/presentation/notes_list_screen.dart';
import 'package:supanotes/features/search/presentation/search_screen.dart';
import 'package:supanotes/features/settings/presentation/contexts_screen.dart';
import 'package:supanotes/features/settings/presentation/settings_screen.dart';
import 'package:supanotes/features/settings/presentation/soul_editor_screen.dart';
import 'package:supanotes/features/routines/presentation/brief_history_screen.dart';
import 'package:supanotes/features/routines/presentation/routines_screen.dart';
import 'package:supanotes/features/telegram/presentation/telegram_link_screen.dart';
import 'package:supanotes/shared/widgets/splash_screen.dart';

final goRouterProvider = Provider<GoRouter>((ref) {
  final notifier = ValueNotifier<AsyncValue<User?>>(
    ref.read(authControllerProvider),
  );
  ref.listen<AsyncValue<User?>>(
    authControllerProvider,
    (_, next) => notifier.value = next,
  );
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,
    refreshListenable: notifier,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (_, __) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (_, __) => const NotesListScreen(),
      ),
      GoRoute(
        path: AppRoutes.chat,
        builder: (_, __) => const ChatScreen(),
      ),
      GoRoute(
        path: AppRoutes.search,
        builder: (_, __) => const SearchScreen(),
      ),
      GoRoute(
        path: AppRoutes.inbox,
        builder: (_, __) => const InboxScreen(),
      ),
      GoRoute(
        path: AppRoutes.note(':id'),
        builder: (_, state) =>
            NoteEditorScreen(noteId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, __) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.soul,
        builder: (_, __) => const SoulEditorScreen(),
      ),
      GoRoute(
        path: AppRoutes.contexts,
        builder: (_, __) => const ContextsScreen(),
      ),
      GoRoute(
        path: AppRoutes.routines,
        builder: (_, __) => const RoutinesScreen(),
      ),
      GoRoute(
        path: AppRoutes.routinesLogs,
        builder: (_, __) => const BriefHistoryScreen(),
      ),
      GoRoute(
        path: AppRoutes.telegram,
        builder: (_, __) => const TelegramLinkScreen(),
      ),
    ],
    redirect: (context, state) => authGuardRedirect(
      currentLocation: state.matchedLocation,
      authState: notifier.value,
    ),
  );
});
