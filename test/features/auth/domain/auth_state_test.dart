import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';
import 'package:supanotes/features/auth/data/auth_repository.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/auth/domain/user.dart';

class _MockAuthLocalStorage extends Mock implements AuthLocalStorage {}

class _MockAuthRepository extends Mock implements AuthRepository {}

const _storageKey = 'test.storage';
const _repositoryKey = 'test.repository';

void _stubEmptySession(_MockAuthLocalStorage storage) {
  when(() => storage.getAccessToken()).thenAnswer((_) async => null);
  when(() => storage.getRefreshToken()).thenAnswer((_) async => null);
  when(() => storage.getUser()).thenAnswer((_) async => null);
  when(() => storage.clear()).thenAnswer((_) async {});
}

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

/// Triggers the notifier's build() and flushes the _restore microtask.
Future<void> waitForBuild(ProviderContainer container) async {
  container.read(authControllerProvider);
  await Future(() {});
}

void main() {
  group('AuthController.build', () {
    test('sets null when no access token is stored', () async {
      final storage = _MockAuthLocalStorage();
      final repository = _MockAuthRepository();
      when(() => storage.getAccessToken()).thenAnswer((_) async => null);
      when(() => storage.getUser()).thenAnswer((_) async => null);

      final container = makeContainer(
        storage: storage,
        repository: repository,
      );
      await waitForBuild(container);
      final user = container.read(authControllerProvider).requireValue;
      expect(user, isNull);
    });

    test('sets null when the token is empty', () async {
      final storage = _MockAuthLocalStorage();
      final repository = _MockAuthRepository();
      when(() => storage.getAccessToken()).thenAnswer((_) async => '');

      final container = makeContainer(
        storage: storage,
        repository: repository,
      );
      await waitForBuild(container);
      final user = container.read(authControllerProvider).requireValue;
      expect(user, isNull);
    });

    test('sets User when full session is on disk', () async {
      final storage = _MockAuthLocalStorage();
      final repository = _MockAuthRepository();
      when(() => storage.getAccessToken()).thenAnswer((_) async => 'tok');
      when(() => storage.getUser()).thenAnswer(
        (_) async => const User(id: 'u-1', email: 'a@b', name: 'Alice'),
      );

      final container = makeContainer(
        storage: storage,
        repository: repository,
      );
      await waitForBuild(container);
      final user = container.read(authControllerProvider).requireValue;
      expect(user, isA<User>());
      expect(user!.id, 'u-1');
      expect(user.email, 'a@b');
      expect(user.name, 'Alice');
    });

    test('wipes storage and sets null on partial session', () async {
      final storage = _MockAuthLocalStorage();
      final repository = _MockAuthRepository();
      when(() => storage.getAccessToken()).thenAnswer((_) async => 'tok');
      when(() => storage.getUser()).thenAnswer((_) async => null);
      when(() => storage.clear()).thenAnswer((_) async {});

      final container = makeContainer(
        storage: storage,
        repository: repository,
      );
      await waitForBuild(container);
      final user = container.read(authControllerProvider).requireValue;
      expect(user, isNull);
      verify(() => storage.clear()).called(1);
    });
  });

  group('AuthController.login', () {
    test('on success, sets User with the returned data', () async {
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

      final container = makeContainer(
        storage: storage,
        repository: repository,
      );
      await waitForBuild(container);

      final result = await container
          .read(authControllerProvider.notifier)
          .login(email: 'a@b.com', password: 'hunter2hunter2');

      expect(result.user.id, 'u-1');
      final user = container.read(authControllerProvider).requireValue;
      expect(user, isA<User>());
      expect(user!.id, 'u-1');
      expect(user.email, 'a@b.com');
      expect(user.name, 'Alice');
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
      await waitForBuild(container);

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
    test('on success, sets User with the returned data', () async {
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
            session: SessionData(
              settings: {},
              soul: {},
              contexts: [],
              routines: [],
            ),
          ));

      final container = makeContainer(
        storage: storage,
        repository: repository,
      );
      await waitForBuild(container);

      await container.read(authControllerProvider.notifier).register(
            email: 'b@c.com',
            password: 'hunter2hunter2',
            name: 'Bob',
          );

      final user = container.read(authControllerProvider).requireValue;
      expect(user, isA<User>());
      expect(user!.id, 'u-2');
    });
  });

  group('AuthController.logout', () {
    test('on success, sets null', () async {
      final storage = _MockAuthLocalStorage();
      final repository = _MockAuthRepository();
      _stubEmptySession(storage);
      when(() => repository.logout()).thenAnswer((_) async {});

      final container = makeContainer(
        storage: storage,
        repository: repository,
      );
      await waitForBuild(container);

      await container.read(authControllerProvider.notifier).logout();
      final user = container.read(authControllerProvider).requireValue;
      expect(user, isNull);
      verify(() => repository.logout()).called(1);
    });

    test('on ApiException, still sets null', () async {
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
      await waitForBuild(container);

      await container.read(authControllerProvider.notifier).logout();
      final user = container.read(authControllerProvider).requireValue;
      expect(user, isNull);
    });
  });

  group('AuthController.onSessionExpired', () {
    test('clears storage and sets null', () async {
      final storage = _MockAuthLocalStorage();
      final repository = _MockAuthRepository();
      _stubEmptySession(storage);
      when(() => storage.clear()).thenAnswer((_) async {});

      final container = makeContainer(
        storage: storage,
        repository: repository,
      );
      await waitForBuild(container);

      await container
          .read(authControllerProvider.notifier)
          .onSessionExpired();
      final user = container.read(authControllerProvider).requireValue;
      expect(user, isNull);
      verify(() => storage.clear()).called(1);
    });
  });
}

// Suppress unused-import warnings for keys that are only used as labels.
// ignore: unused_element
const _ = (_storageKey, _repositoryKey);
