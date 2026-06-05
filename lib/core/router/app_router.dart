/// [GoRouter] configuration and the Riverpod provider that exposes it.
///
/// The router is built once per provider lifetime. A [ValueNotifier]
/// mirroring the current [authControllerProvider] is handed to
/// [GoRouter.refreshListenable] so go_router re-evaluates the redirect
/// every time the auth state changes, without us having to replace the
/// whole [GoRouter] instance (which would reset history and cause a
/// visible flash). The actual decision logic lives in
/// [authGuardRedirect] in `auth_guard.dart` and is exercised there in
/// isolation; this file is mostly glue.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/router/auth_guard.dart';
import 'package:supanotes/features/auth/domain/auth_state.dart';
import 'package:supanotes/features/auth/presentation/login_screen.dart';
import 'package:supanotes/features/auth/presentation/register_screen.dart';
import 'package:supanotes/features/notes/presentation/inbox_screen.dart';
import 'package:supanotes/features/notes/presentation/note_editor_screen.dart';
import 'package:supanotes/features/notes/presentation/notes_list_screen.dart';
import 'package:supanotes/shared/widgets/splash_screen.dart';

/// Application [GoRouter] driven by the current [authControllerProvider].
///
/// The [ValueNotifier] is seeded with whatever the provider currently
/// holds (typically [AsyncLoading] on first build, then transitioning
/// to [AsyncData] of the resolved [AuthState]), and updated via
/// [Ref.listen] every time the auth controller emits a new value. The
/// router consults the notifier's current value inside its `redirect`
/// callback, so the rule always sees the latest auth snapshot.
final goRouterProvider = Provider<GoRouter>((ref) {
  final notifier = ValueNotifier<AsyncValue<AuthState>>(
    ref.read(authControllerProvider),
  );
  ref.listen<AsyncValue<AuthState>>(
    authControllerProvider,
    (_, next) => notifier.value = next,
  );
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: false,
    refreshListenable: notifier,
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (_, __) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (_, __) => const NotesListScreen(),
      ),
      GoRoute(
        path: '/inbox',
        builder: (_, __) => const InboxScreen(),
      ),
      GoRoute(
        path: '/notes/:id',
        builder: (_, state) =>
            NoteEditorScreen(noteId: state.pathParameters['id']!),
      ),
    ],
    redirect: (context, state) => authGuardRedirect(
      currentLocation: state.matchedLocation,
      authState: notifier.value,
    ),
  );
});
