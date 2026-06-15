import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';
import 'package:supanotes/features/auth/data/auth_repository.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/auth/domain/user.dart';
import 'package:supanotes/features/auth/presentation/login_screen.dart';
import 'package:supanotes/shared/theme/app_theme.dart';

class _MockAuthLocalStorage extends Mock implements AuthLocalStorage {}

class _MockAuthRepository extends Mock implements AuthRepository {}

void _stubEmptySession(_MockAuthLocalStorage storage) {
  when(() => storage.getAccessToken()).thenAnswer((_) async => null);
  when(() => storage.getRefreshToken()).thenAnswer((_) async => null);
  when(() => storage.getUser()).thenAnswer((_) async => null);
  when(() => storage.getSessionData()).thenAnswer((_) async => const {});
  when(() => storage.saveSessionData(any())).thenAnswer((_) async {});
  when(() => storage.saveTokens(
        accessToken: any(named: 'accessToken'),
        refreshToken: any(named: 'refreshToken'),
      )).thenAnswer((_) async {});
  when(() => storage.saveUser(user: any(named: 'user'))).thenAnswer((_) async {});
  when(() => storage.clear()).thenAnswer((_) async {});
}

Widget _wrap(Widget child, {required ProviderContainer container}) {
  final router = GoRouter(
    initialLocation: AppRoutes.login,
    routes: [
      GoRoute(path: AppRoutes.login, builder: (_, __) => child),
      GoRoute(
        path: AppRoutes.register,
        builder: (_, __) => const Scaffold(body: Text('register-stub')),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (_, __) => const Scaffold(body: Text('home-stub')),
      ),
    ],
  );
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      routerConfig: router,
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(const User(id: '', email: '', name: ''));
  });

  testWidgets('renders the title and both fields', (tester) async {
    final storage = _MockAuthLocalStorage();
    final repository = _MockAuthRepository();
    _stubEmptySession(storage);
    final container = ProviderContainer(
      overrides: [
        authLocalStorageProvider.overrideWithValue(storage),
        authRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(const LoginScreen(), container: container));
    await tester.pump();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text("Don't have an account? Create one"), findsOneWidget);
  });

  testWidgets('shows validation errors on empty submit', (tester) async {
    final storage = _MockAuthLocalStorage();
    final repository = _MockAuthRepository();
    _stubEmptySession(storage);
    final container = ProviderContainer(
      overrides: [
        authLocalStorageProvider.overrideWithValue(storage),
        authRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(const LoginScreen(), container: container));
    await tester.pump();
    await tester.tap(find.text('Sign in'));
    await tester.pump();

    expect(find.text('Email é obrigatório'), findsOneWidget);
    expect(find.text('Senha é obrigatória'), findsOneWidget);
    verifyNever(() => repository.login(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ));
  });

  testWidgets('rejects an invalid email', (tester) async {
    final storage = _MockAuthLocalStorage();
    final repository = _MockAuthRepository();
    _stubEmptySession(storage);
    final container = ProviderContainer(
      overrides: [
        authLocalStorageProvider.overrideWithValue(storage),
        authRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(const LoginScreen(), container: container));
    await tester.pump();
    await tester.enterText(find.byType(TextFormField).at(0), 'not-an-email');
    await tester.enterText(find.byType(TextFormField).at(1), 'hunter2hunter2');
    await tester.tap(find.text('Sign in'));
    await tester.pump();

    expect(find.text('Email inválido'), findsOneWidget);
    verifyNever(() => repository.login(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ));
  });

  testWidgets(
      'on success, calls the repository and lets the controller flip state',
      (tester) async {
    final storage = _MockAuthLocalStorage();
    final repository = _MockAuthRepository();
    _stubEmptySession(storage);
    when(() => repository.login(
          email: any(named: 'email'),
          password: any(named: 'password'),
        )).thenAnswer((_) async => const AuthResult(
          user: User(id: 'u-1', email: 'a@b.com', name: 'Alice'),
          accessToken: 'a',
          refreshToken: 'r',
          session: SessionData(
            settings: {},
            soul: {},
            contexts: [],
            routines: [],
          ),
        ));

    final container = ProviderContainer(
      overrides: [
        authLocalStorageProvider.overrideWithValue(storage),
        authRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(const LoginScreen(), container: container));
    await tester.pump();
    await tester.enterText(find.byType(TextFormField).at(0), 'a@b.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'hunter2hunter2');
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    await tester.pump();

    verify(() => repository.login(
          email: 'a@b.com',
          password: 'hunter2hunter2',
        )).called(1);
    expect(
      container.read(authControllerProvider).requireValue,
      isNotNull,
    );
  });

  testWidgets('on 401, surfaces a snackbar with the error message',
      (tester) async {
    final storage = _MockAuthLocalStorage();
    final repository = _MockAuthRepository();
    _stubEmptySession(storage);
    when(() => repository.login(
          email: any(named: 'email'),
          password: any(named: 'password'),
        )).thenThrow(
      const UnauthorizedException(message: 'wrong password'),
    );

    final container = ProviderContainer(
      overrides: [
        authLocalStorageProvider.overrideWithValue(storage),
        authRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(const LoginScreen(), container: container));
    await tester.pump();
    await tester.enterText(find.byType(TextFormField).at(0), 'a@b.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'wrongpassword');
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    await tester.pump();

    expect(find.text('wrong password'), findsOneWidget);
  });
}
