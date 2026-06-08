import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';
import 'package:supanotes/features/auth/data/auth_repository.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/auth/domain/auth_state.dart';
import 'package:supanotes/features/auth/domain/user.dart';

class _MockAuthLocalStorage extends Mock implements AuthLocalStorage {}

class _MockAuthRepository extends Mock implements AuthRepository {}

const _storageKey = 'test.storage';
const _repositoryKey = 'test.repository';

void _stubEmptySession(_MockAuthLocalStorage storage) {
  when(() => storage.getAccessToken()).thenAnswer((_) async => null);
  when(() => storage.getRefreshToken()).thenAnswer((_) async => null);
  when(() => storage.getUserId()).thenAnswer((_) async => null);
  when(() => storage.getUserEmail()).thenAnswer((_) async => null);
  when(() => storage.getUserName()).thenAnswer((_) async => null);
  when(() => storage.clear()).thenAnswer((_) async {});
}

void main() {
  setUpAll(() {
    registerFallbackValue(const AuthAuthenticated(
      User(id: '', email: '', name: ''),
    ));
  });

  ProviderContainer makeContainer({
    required AuthLocalStorage storage,
    required AuthRepository repository,
  }) {
    final container = ProviderContainer(
      overrides: [
        authLocalStorageProvider.overrideWithValue(storage),
        authRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('AuthState', () {
    test('sealed class variants are equal to themselves', () {
      expect(const AuthUnauthenticated(), const AuthUnauthenticated());
      expect(
        const AuthAuthenticated(User(id: 'u', email: 'e', name: 'n')),
        const AuthAuthenticated(User(id: 'u', email: 'e', name: 'n')),
      );
    });

    test('two AuthAuthenticated with different fields are not equal', () {
      const a = AuthAuthenticated(User(id: '1', email: 'a', name: 'A'));
      const b = AuthAuthenticated(User(id: '2', email: 'b', name: 'B'));
      expect(a == b, isFalse);
    });
  });

  group('AuthController.build', () {
    test('returns AuthUnauthenticated when no access token is stored',
        () async {
      final storage = _MockAuthLocalStorage();
      final repository = _MockAuthRepository();
      when(() => storage.getAccessToken()).thenAnswer((_) async => null);
      when(() => storage.getRefreshToken()).thenAnswer((_) async => null);
      when(() => storage.getUserId()).thenAnswer((_) async => null);
      when(() => storage.getUserEmail()).thenAnswer((_) async => null);
      when(() => storage.getUserName()).thenAnswer((_) async => null);

      final container = makeContainer(
        storage: storage,
        repository: repository,
      );
      final state = await container.read(authControllerProvider.future);
      expect(state, isA<AuthUnauthenticated>());
    });

    test('returns AuthUnauthenticated when the token is empty', () async {
      final storage = _MockAuthLocalStorage();
      final repository = _MockAuthRepository();
      when(() => storage.getAccessToken()).thenAnswer((_) async => '');
      when(() => storage.getUserId()).thenAnswer((_) async => null);
      when(() => storage.getUserEmail()).thenAnswer((_) async => null);
      when(() => storage.getUserName()).thenAnswer((_) async => null);

      final container = makeContainer(
        storage: storage,
        repository: repository,
      );
      final state = await container.read(authControllerProvider.future);
      expect(state, isA<AuthUnauthenticated>());
    });

    test('returns AuthAuthenticated when full session is on disk', () async {
      final storage = _MockAuthLocalStorage();
      final repository = _MockAuthRepository();
      when(() => storage.getAccessToken()).thenAnswer((_) async => 'tok');
      when(() => storage.getUserId()).thenAnswer((_) async => 'u-1');
      when(() => storage.getUserEmail()).thenAnswer((_) async => 'a@b');
      when(() => storage.getUserName()).thenAnswer((_) async => 'Alice');

      final container = makeContainer(
        storage: storage,
        repository: repository,
      );
      final state = await container.read(authControllerProvider.future);
      expect(state, isA<AuthAuthenticated>());
      expect((state as AuthAuthenticated).user.id, 'u-1');
      expect(state.user.email, 'a@b');
      expect(state.user.name, 'Alice');
    });

    test('wipes storage and returns Unauthenticated on partial session',
        () async {
      final storage = _MockAuthLocalStorage();
      final repository = _MockAuthRepository();
      when(() => storage.getAccessToken()).thenAnswer((_) async => 'tok');
      when(() => storage.getUserId()).thenAnswer((_) async => 'u-1');
      when(() => storage.getUserEmail()).thenAnswer((_) async => null);
      when(() => storage.getUserName()).thenAnswer((_) async => null);
      when(() => storage.clear()).thenAnswer((_) async {});

      final container = makeContainer(
        storage: storage,
        repository: repository,
      );
      final state = await container.read(authControllerProvider.future);
      expect(state, isA<AuthUnauthenticated>());
      verify(() => storage.clear()).called(1);
    });
  });

  group('AuthController.login', () {
    test('on success, emits AuthAuthenticated with the user fields',
        () async {
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

      final container = makeContainer(
        storage: storage,
        repository: repository,
      );
      // First read to build the notifier.
      await container.read(authControllerProvider.future);

      final result = await container
          .read(authControllerProvider.notifier)
          .login(email: 'a@b.com', password: 'hunter2hunter2');

      expect(result.user.id, 'u-1');
      final state = container.read(authControllerProvider).requireValue;
      expect(state, isA<AuthAuthenticated>());
      final auth = state as AuthAuthenticated;
      expect(auth.user.id, 'u-1');
      expect(auth.user.email, 'a@b.com');
      expect(auth.user.name, 'Alice');
    });

    test('on failure, rethrows and stores the error in state', () async {
      final storage = _MockAuthLocalStorage();
      final repository = _MockAuthRepository();
      _stubEmptySession(storage);
      when(() => repository.login(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenThrow(
        const UnauthorizedException(message: 'wrong password'),
      );

      final container = makeContainer(
        storage: storage,
        repository: repository,
      );
      await container.read(authControllerProvider.future);

      await expectLater(
        () => container
            .read(authControllerProvider.notifier)
            .login(email: 'a@b.com', password: 'wrong'),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(
        container.read(authControllerProvider).hasError,
        isTrue,
      );
    });
  });

  group('AuthController.register', () {
    test('on success, emits AuthAuthenticated', () async {
      final storage = _MockAuthLocalStorage();
      final repository = _MockAuthRepository();
      _stubEmptySession(storage);
      when(() => repository.register(
            email: any(named: 'email'),
            password: any(named: 'password'),
            name: any(named: 'name'),
          )).thenAnswer((_) async => const AuthResult(
            user: User(id: 'u-2', email: 'b@c.com', name: 'Bob'),
            accessToken: 'a',
            refreshToken: 'r',
          ));

      final container = makeContainer(
        storage: storage,
        repository: repository,
      );
      await container.read(authControllerProvider.future);

      await container.read(authControllerProvider.notifier).register(
            email: 'b@c.com',
            password: 'hunter2hunter2',
            name: 'Bob',
          );

      final state = container.read(authControllerProvider).requireValue;
      expect(state, isA<AuthAuthenticated>());
      expect((state as AuthAuthenticated).user.id, 'u-2');
    });
  });

  group('AuthController.logout', () {
    test('on success, emits AuthUnauthenticated', () async {
      final storage = _MockAuthLocalStorage();
      final repository = _MockAuthRepository();
      _stubEmptySession(storage);
      when(() => repository.logout()).thenAnswer((_) async {});

      final container = makeContainer(
        storage: storage,
        repository: repository,
      );
      await container.read(authControllerProvider.future);

      await container.read(authControllerProvider.notifier).logout();
      final state = container.read(authControllerProvider).requireValue;
      expect(state, isA<AuthUnauthenticated>());
      verify(() => repository.logout()).called(1);
    });

    test('on ApiException, still ends in AuthUnauthenticated', () async {
      final storage = _MockAuthLocalStorage();
      final repository = _MockAuthRepository();
      _stubEmptySession(storage);
      when(() => repository.logout()).thenThrow(
        const NetworkException(message: 'offline'),
      );

      final container = makeContainer(
        storage: storage,
        repository: repository,
      );
      await container.read(authControllerProvider.future);

      await container.read(authControllerProvider.notifier).logout();
      final state = container.read(authControllerProvider).requireValue;
      expect(state, isA<AuthUnauthenticated>());
    });
  });

  group('AuthController.onSessionExpired', () {
    test('clears storage and emits AuthUnauthenticated', () async {
      final storage = _MockAuthLocalStorage();
      final repository = _MockAuthRepository();
      _stubEmptySession(storage);
      when(() => storage.clear()).thenAnswer((_) async {});

      final container = makeContainer(
        storage: storage,
        repository: repository,
      );
      await container.read(authControllerProvider.future);

      await container
          .read(authControllerProvider.notifier)
          .onSessionExpired();
      final state = container.read(authControllerProvider).requireValue;
      expect(state, isA<AuthUnauthenticated>());
      verify(() => storage.clear()).called(1);
    });
  });
}

// Suppress unused-import warnings for keys that are only used as labels.
// ignore: unused_element
const _ = (_storageKey, _repositoryKey);
