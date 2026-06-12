import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/core/router/app_router.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';
import 'package:supanotes/features/auth/data/auth_repository.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/auth/domain/user.dart';
import 'package:supanotes/features/auth/presentation/controllers/auth_controller.dart';
import 'package:supanotes/shared/theme/app_theme.dart';
import 'package:supanotes/core/router/last_route_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockAuthLocalStorage extends Mock implements AuthLocalStorage {}

class _MockAuthRepository extends Mock implements AuthRepository {}

class _StubAuthController extends AuthController {
  _StubAuthController(this._stub);

  final AsyncValue<User?> _stub;

  @override
  AsyncValue<User?> build() => _stub;
}

void _stubEmptySession(_MockAuthLocalStorage storage) {
  when(() => storage.getAccessToken()).thenAnswer((_) async => null);
  when(() => storage.getRefreshToken()).thenAnswer((_) async => null);
  when(() => storage.getUser()).thenAnswer((_) async => null);
  when(() => storage.clear()).thenAnswer((_) async {});
}

Future<ProviderContainer> _makeContainer(
  AsyncValue<User?> stub, {
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

  testWidgets('starting with loading auth redirects to /login', (tester) async {
    final stub = AsyncValue<User?>.loading();
    final container = await _makeContainer(stub);

    await tester.pumpWidget(_wrapRouter(container));
    await settleRedirect(tester);

    final router = container.read(goRouterProvider);
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      AppRoutes.login,
    );
  });

  testWidgets('starting on /login with unauth auth stays on /login',
      (tester) async {
    final stub = AsyncValue<User?>.data(null);
    final container = await await _makeContainer(stub);

    await tester.pumpWidget(_wrapRouter(container));
    await settleRedirect(tester);

    final router = container.read(goRouterProvider);
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      AppRoutes.login,
    );
  });

  testWidgets('starting on /login with auth redirects to /home', (tester) async {
    final stub = AsyncValue<User?>.data(
      const User(id: 'u-1', email: 'a@b.com', name: 'Alice'),
    );
    final container = await _makeContainer(stub);

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
    final stub = AsyncValue<User?>.data(null);
    final container = await _makeContainer(stub);

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
    final stub = AsyncValue<User?>.data(null);
    final container = await _makeContainer(stub);

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
    final stub = AsyncValue<User?>.data(
      const User(id: 'u-1', email: 'a@b.com', name: 'Alice'),
    );
    final container = await _makeContainer(stub);

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
    final stub = AsyncValue<User?>.data(
      const User(id: 'u-1', email: 'a@b.com', name: 'Alice'),
    );
    final container = await _makeContainer(stub);

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
    final stub = AsyncValue<User?>.data(
      const User(id: 'u-1', email: 'a@b.com', name: 'Alice'),
    );
    final container = await _makeContainer(stub);

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

  testWidgets('authenticated startup opens the persisted note route', (tester) async {
    final stub = AsyncValue<User?>.data(
      const User(id: 'u-1', email: 'a@b.com', name: 'Alice'),
    );
    final container = await _makeContainer(
      stub,
      prefs: {'last_route': '/notes/note-1'},
    );

    await tester.pumpWidget(_wrapRouter(container));
    await settleRedirect(tester);

    final router = container.read(goRouterProvider);
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      '/notes/note-1',
    );
  });
}
