import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supanotes/core/router/app_router.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';
import 'package:supanotes/features/auth/data/auth_repository.dart';
import 'package:supanotes/features/auth/domain/user.dart';
import 'package:supanotes/features/auth/presentation/controllers/auth_controller.dart';
import 'package:supanotes/shared/theme/app_theme.dart';

class _MockAuthLocalStorage extends Mock implements AuthLocalStorage {}

class _MockAuthRepository extends Mock implements AuthRepository {}

class _StubAuthController extends AuthController {
  _StubAuthController(this._user);

  final User? _user;

  @override
  Future<User?> build() async => _user;
}

// Documenta que isso força o estado loading indefinidamente
class _LoadingAuthController extends AuthController {
  @override
  Future<User?> build() => Completer<User?>().future; // nunca completa → loading
}

void _stubEmptySession(_MockAuthLocalStorage storage) {
  when(() => storage.getAccessToken()).thenAnswer((_) async => null);
  when(() => storage.getRefreshToken()).thenAnswer((_) async => null);
  when(() => storage.getUser()).thenAnswer((_) async => null);
  when(() => storage.clear()).thenAnswer((_) async {});
}

Future<ProviderContainer> _makeContainer(
  User? stub, {
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sharedPreferences = await SharedPreferences.getInstance();
  final storage = _MockAuthLocalStorage();
  final repository = _MockAuthRepository();
  _stubEmptySession(storage);
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      authLocalStorageProvider.overrideWithValue(storage),
      authRepositoryProvider.overrideWithValue(repository),
      authControllerProvider.overrideWith(() => _StubAuthController(stub)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<ProviderContainer> _makeLoadingContainer({
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sharedPreferences = await SharedPreferences.getInstance();
  final storage = _MockAuthLocalStorage();
  final repository = _MockAuthRepository();
  _stubEmptySession(storage);
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      authLocalStorageProvider.overrideWithValue(storage),
      authRepositoryProvider.overrideWithValue(repository),
      authControllerProvider.overrideWith(
        () => _LoadingAuthController(),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Widget _wrapRouter(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: Consumer(
      builder: (context, ref, _) {
        final router = ref.watch(goRouterProvider);
        return MaterialApp.router(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.light,
          routerConfig: router,
        );
      },
    ),
  );
}



void main() {
  Future<void> settleRedirect(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('starting with loading auth lands on /splash', (tester) async {
    final container = await _makeLoadingContainer();

    await tester.pumpWidget(_wrapRouter(container));
    await settleRedirect(tester);

    final router = container.read(goRouterProvider);
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      AppRoutes.splash,
    );
  });

  testWidgets('starting on /splash with unauth auth redirects to /login',
      (tester) async {
    final container = await _makeContainer(null);

    await tester.pumpWidget(_wrapRouter(container));
    await settleRedirect(tester);

    final router = container.read(goRouterProvider);
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      AppRoutes.login,
    );
  });

  testWidgets('starting on /splash with auth redirects to /home', (tester) async {
    final container = await _makeContainer(
      const User(id: 'u-1', email: 'a@b.com', name: 'Alice'),
    );

    await tester.pumpWidget(_wrapRouter(container));
    await settleRedirect(tester);

    final router = container.read(goRouterProvider);
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      AppRoutes.home,
    );
  });

  testWidgets('starting on /login with unauth auth stays on /login',
      (tester) async {
    final container = await _makeContainer(null);

    await tester.pumpWidget(_wrapRouter(container));
    await settleRedirect(tester);

    final router = container.read(goRouterProvider);
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      AppRoutes.login,
    );
  });

  testWidgets('starting on /login with auth redirects to /home', (tester) async {
    final container = await _makeContainer(
      const User(id: 'u-1', email: 'a@b.com', name: 'Alice'),
    );

    await tester.pumpWidget(_wrapRouter(container));
    await settleRedirect(tester);

    final router = container.read(goRouterProvider);
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      AppRoutes.home,
    );
  });

  testWidgets('unauthenticated user on /home is redirected to /login',
      (tester) async {
    final container = await _makeContainer(null);

    await tester.pumpWidget(_wrapRouter(container));
    await settleRedirect(tester);

    final router = container.read(goRouterProvider);
    router.go(AppRoutes.home);
    await settleRedirect(tester);

    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      AppRoutes.login,
    );
  });

  testWidgets('unauthenticated user on /register is left at /register',
      (tester) async {
    final container = await _makeContainer(null);

    await tester.pumpWidget(_wrapRouter(container));
    await settleRedirect(tester);

    final router = container.read(goRouterProvider);
    router.go(AppRoutes.register);
    await settleRedirect(tester);

    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      AppRoutes.register,
    );
  });

  testWidgets('authenticated user on /login is redirected to /home',
      (tester) async {
    final container = await _makeContainer(
      const User(id: 'u-1', email: 'a@b.com', name: 'Alice'),
    );

    await tester.pumpWidget(_wrapRouter(container));
    await settleRedirect(tester);

    final router = container.read(goRouterProvider);
    router.go(AppRoutes.login);
    await settleRedirect(tester);

    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      AppRoutes.home,
    );
  });

  testWidgets('authenticated user on /register is redirected to /home',
      (tester) async {
    final container = await _makeContainer(
      const User(id: 'u-1', email: 'a@b.com', name: 'Alice'),
    );

    await tester.pumpWidget(_wrapRouter(container));
    await settleRedirect(tester);

    final router = container.read(goRouterProvider);
    router.go(AppRoutes.register);
    await settleRedirect(tester);

    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      AppRoutes.home,
    );
  });

  testWidgets('authenticated user on /home stays at /home', (tester) async {
    final container = await _makeContainer(
      const User(id: 'u-1', email: 'a@b.com', name: 'Alice'),
    );

    await tester.pumpWidget(_wrapRouter(container));
    await settleRedirect(tester);

    final router = container.read(goRouterProvider);
    router.go(AppRoutes.home);
    await settleRedirect(tester);

    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      AppRoutes.home,
    );
  });

}
