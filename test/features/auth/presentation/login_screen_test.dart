import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';
import 'package:supanotes/features/auth/data/auth_repository.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/auth/domain/auth_state.dart';
import 'package:supanotes/features/auth/domain/user.dart';
import 'package:supanotes/features/auth/presentation/login_screen.dart';
import 'package:supanotes/shared/theme/app_theme.dart';

class _MockAuthLocalStorage extends Mock implements AuthLocalStorage {}

class _MockAuthRepository extends Mock implements AuthRepository {}

void _stubEmptySession(_MockAuthLocalStorage storage) {
  when(() => storage.getAccessToken()).thenAnswer((_) async => null);
  when(() => storage.getRefreshToken()).thenAnswer((_) async => null);
  when(() => storage.getUserId()).thenAnswer((_) async => null);
  when(() => storage.getUserEmail()).thenAnswer((_) async => null);
  when(() => storage.getUserName()).thenAnswer((_) async => null);
  when(() => storage.clear()).thenAnswer((_) async {});
}

Widget _wrap(Widget child, {required ProviderContainer container}) {
  final router = GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(path: '/login', builder: (_, __) => child),
      GoRoute(
        path: '/register',
        builder: (_, __) => const Scaffold(body: Text('register-stub')),
      ),
      GoRoute(
        path: '/home',
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
    registerFallbackValue(
      const AuthAuthenticated(userId: '', email: '', name: ''),
    );
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

    expect(find.text('Email is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);
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

    expect(find.text('Enter a valid email address'), findsOneWidget);
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
      isA<AuthAuthenticated>(),
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
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong');
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    await tester.pump();

    expect(find.text('wrong password'), findsOneWidget);
  });
}
