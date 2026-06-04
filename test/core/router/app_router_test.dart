import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/core/router/app_router.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';
import 'package:supanotes/features/auth/data/auth_repository.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/auth/domain/auth_state.dart';
import 'package:supanotes/features/auth/presentation/controllers/auth_controller.dart';
import 'package:supanotes/shared/theme/app_theme.dart';
import 'package:supanotes/shared/widgets/splash_screen.dart';

class _MockAuthLocalStorage extends Mock implements AuthLocalStorage {}

class _MockAuthRepository extends Mock implements AuthRepository {}

/// Stub [AuthController] that returns a fixed [AsyncValue] for [build].
///
/// The real `AuthController.build()` reads from secure storage and the
/// repository; for router tests we drive the state machine
/// deterministically, so we short-circuit [build] to return whatever the
/// test specifies.
class _StubAuthController extends AuthController {
  _StubAuthController(this._stub);

  final AsyncValue<AuthState> _stub;

  @override
  Future<AuthState> build() async => _stub.value as AuthState;
}

void _stubEmptySession(_MockAuthLocalStorage storage) {
  when(() => storage.getAccessToken()).thenAnswer((_) async => null);
  when(() => storage.getRefreshToken()).thenAnswer((_) async => null);
  when(() => storage.getUserId()).thenAnswer((_) async => null);
  when(() => storage.getUserEmail()).thenAnswer((_) async => null);
  when(() => storage.getUserName()).thenAnswer((_) async => null);
  when(() => storage.clear()).thenAnswer((_) async {});
}

ProviderContainer _makeContainer(AsyncValue<AuthState> stub) {
  final storage = _MockAuthLocalStorage();
  final repository = _MockAuthRepository();
  _stubEmptySession(storage);
  final container = ProviderContainer(
    overrides: [
      authLocalStorageProvider.overrideWithValue(storage),
      authRepositoryProvider.overrideWithValue(repository),
      authControllerProvider.overrideWith(() => _StubAuthController(stub)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Wraps the router inside an [UncontrolledProviderScope] so the routed
/// ConsumerWidgets ([HomeScreen], [LoginScreen], etc.) can resolve
/// [authControllerProvider] when they build.
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

const _login = '/login';
const _register = '/register';
const _home = '/home';
const _splash = '/';

void main() {
  testWidgets('starting on / renders the splash', (tester) async {
    const stub = AsyncValue<AuthState>.data(AuthUnauthenticated());
    final container = _makeContainer(stub);

    await tester.pumpWidget(_wrapRouter(container));
    await tester.pump();

    expect(find.byType(SplashScreen), findsOneWidget);
    final router = container.read(goRouterProvider);
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      _splash,
    );
  });

  testWidgets('unauthenticated user on /home is redirected to /login',
      (tester) async {
    const stub = AsyncValue<AuthState>.data(AuthUnauthenticated());
    final container = _makeContainer(stub);

    await tester.pumpWidget(_wrapRouter(container));
    await tester.pump();

    final router = container.read(goRouterProvider);
    router.go(_home);
    await tester.pump();

    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      _login,
    );
  });

  testWidgets('unauthenticated user on /register is left at /register',
      (tester) async {
    const stub = AsyncValue<AuthState>.data(AuthUnauthenticated());
    final container = _makeContainer(stub);

    await tester.pumpWidget(_wrapRouter(container));
    await tester.pump();

    final router = container.read(goRouterProvider);
    router.go(_register);
    await tester.pump();

    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      _register,
    );
  });

  testWidgets('authenticated user on /login is redirected to /home',
      (tester) async {
    const stub = AsyncValue<AuthState>.data(
      AuthAuthenticated(userId: 'u-1', email: 'a@b.com', name: 'Alice'),
    );
    final container = _makeContainer(stub);

    await tester.pumpWidget(_wrapRouter(container));
    await tester.pump();

    final router = container.read(goRouterProvider);
    router.go(_login);
    await tester.pump();

    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      _home,
    );
  });

  testWidgets('authenticated user on /register is redirected to /home',
      (tester) async {
    const stub = AsyncValue<AuthState>.data(
      AuthAuthenticated(userId: 'u-1', email: 'a@b.com', name: 'Alice'),
    );
    final container = _makeContainer(stub);

    await tester.pumpWidget(_wrapRouter(container));
    await tester.pump();

    final router = container.read(goRouterProvider);
    router.go(_register);
    await tester.pump();

    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      _home,
    );
  });

  testWidgets('authenticated user on /home stays at /home', (tester) async {
    const stub = AsyncValue<AuthState>.data(
      AuthAuthenticated(userId: 'u-1', email: 'a@b.com', name: 'Alice'),
    );
    final container = _makeContainer(stub);

    await tester.pumpWidget(_wrapRouter(container));
    await tester.pump();

    final router = container.read(goRouterProvider);
    router.go(_home);
    await tester.pump();

    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      _home,
    );
  });
}
