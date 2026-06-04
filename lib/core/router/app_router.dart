/// [GoRouter] configuration and the Riverpod provider that exposes it.
///
/// The router is wired to the [authControllerProvider] so it can re-run
/// the redirect rule every time the auth state changes. The actual
/// decision logic lives in [authGuardRedirect] in `auth_guard.dart` and
/// is exercised there in isolation; this file is mostly glue.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/router/auth_guard.dart';
import 'package:supanotes/features/auth/presentation/home_screen.dart';
import 'package:supanotes/features/auth/presentation/login_screen.dart';
import 'package:supanotes/features/auth/presentation/register_screen.dart';
import 'package:supanotes/shared/widgets/splash_screen.dart';

/// Application [GoRouter] driven by the current [authControllerProvider].
///
/// The router is created lazily on first read; we do not cache it across
/// the app's lifetime because go_router owns its own internal state and
/// Riverpod's auto-dispose model would force a hard rebuild on every
/// auth-state change, which is exactly what we want — the redirect is
/// re-evaluated, the page stack is rewritten, and the user lands on the
/// correct route.
final goRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authControllerProvider);

  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: false,
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
        builder: (_, __) => const HomeScreen(),
      ),
    ],
    redirect: (context, state) => authGuardRedirect(
      currentLocation: state.matchedLocation,
      authState: authState,
    ),
  );
});
