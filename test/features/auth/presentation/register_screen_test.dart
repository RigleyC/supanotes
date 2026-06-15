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
import 'package:supanotes/features/auth/presentation/register_screen.dart';
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
    initialLocation: AppRoutes.register,
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (_, __) => const Scaffold(body: Text('login-stub')),
      ),
      GoRoute(path: AppRoutes.register, builder: (_, __) => child),
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

  testWidgets('renders all four fields and the create button', (tester) async {
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

    await tester.pumpWidget(_wrap(const RegisterScreen(), container: container));
    await tester.pump();

    expect(find.byType(TextFormField), findsNWidgets(4));
    expect(find.text('Create account'), findsOneWidget);
  });

  testWidgets('rejects a password shorter than 8 characters', (tester) async {
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

    await tester.pumpWidget(_wrap(const RegisterScreen(), container: container));
    await tester.pump();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Alice');
    await tester.enterText(fields.at(1), 'a@b.com');
    await tester.enterText(fields.at(2), 'short');
    await tester.enterText(fields.at(3), 'short');
    await tester.tap(find.text('Create account'));
    await tester.pump();

    expect(find.text('Senha deve ter no mínimo 8 caracteres'), findsOneWidget);
    verifyNever(() => repository.register(
          email: any(named: 'email'),
          password: any(named: 'password'),
          name: any(named: 'name'),
        ));
  });

  testWidgets('rejects when the two passwords do not match', (tester) async {
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

    await tester.pumpWidget(_wrap(const RegisterScreen(), container: container));
    await tester.pump();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Alice');
    await tester.enterText(fields.at(1), 'a@b.com');
    await tester.enterText(fields.at(2), 'hunter2hunter2');
    await tester.enterText(fields.at(3), 'different-pw');
    await tester.tap(find.text('Create account'));
    await tester.pump();

    expect(find.text('Senhas não conferem'), findsOneWidget);
    verifyNever(() => repository.register(
          email: any(named: 'email'),
          password: any(named: 'password'),
          name: any(named: 'name'),
        ));
  });

  testWidgets(
      'on a 409, surfaces a snackbar with the error message and does not '
      'flip state', (tester) async {
    final storage = _MockAuthLocalStorage();
    final repository = _MockAuthRepository();
    _stubEmptySession(storage);
    when(() => repository.register(
          email: any(named: 'email'),
          password: any(named: 'password'),
          name: any(named: 'name'),
        )).thenThrow(
      const ConflictException(message: 'email already in use'),
    );

    final container = ProviderContainer(
      overrides: [
        authLocalStorageProvider.overrideWithValue(storage),
        authRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(const RegisterScreen(), container: container));
    await tester.pump();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Alice');
    await tester.enterText(fields.at(1), 'a@b.com');
    await tester.enterText(fields.at(2), 'hunter2hunter2');
    await tester.enterText(fields.at(3), 'hunter2hunter2');
    await tester.tap(find.text('Create account'));
    await tester.pump();
    await tester.pump();

    expect(find.text('email already in use'), findsOneWidget);
    final user = container.read(authControllerProvider).requireValue;
    expect(user, isNull);
  });

  testWidgets(
      'on success, calls the repository and lets the controller flip state',
      (tester) async {
    final storage = _MockAuthLocalStorage();
    final repository = _MockAuthRepository();
    _stubEmptySession(storage);
    when(() => repository.register(
          email: any(named: 'email'),
          password: any(named: 'password'),
          name: any(named: 'name'),
        )).thenAnswer((_) async => const AuthResult(
          user: User(id: 'u-2', email: 'a@b.com', name: 'Alice'),
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

    await tester.pumpWidget(_wrap(const RegisterScreen(), container: container));
    await tester.pump();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Alice');
    await tester.enterText(fields.at(1), 'a@b.com');
    await tester.enterText(fields.at(2), 'hunter2hunter2');
    await tester.enterText(fields.at(3), 'hunter2hunter2');
    await tester.tap(find.text('Create account'));
    await tester.pump();
    await tester.pump();

    verify(() => repository.register(
          email: 'a@b.com',
          password: 'hunter2hunter2',
          name: 'Alice',
        )).called(1);
    final user = container.read(authControllerProvider).requireValue;
    expect(user, isNotNull);
  });
}
