import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/core/auth/auth_token_manager.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';

class _MockAuthLocalStorage extends Mock implements AuthLocalStorage {}

void main() {
  test(
    'loads the access token once and then serves the in-memory value',
    () async {
      final storage = _MockAuthLocalStorage();
      when(() => storage.getAccessToken()).thenAnswer((_) async => 'access-1');
      final manager = AuthTokenManager(storage: storage);

      expect(await manager.getAccessToken(), 'access-1');
      expect(await manager.getAccessToken(), 'access-1');
      verify(() => storage.getAccessToken()).called(1);
    },
  );

  test('install and replace update secure storage and the hot token', () async {
    final storage = _MockAuthLocalStorage();
    when(
      () => storage.saveTokens(
        accessToken: any(named: 'accessToken'),
        refreshToken: any(named: 'refreshToken'),
      ),
    ).thenAnswer((_) async {});
    final manager = AuthTokenManager(storage: storage);

    await manager.installSession(
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
    );
    await manager.replaceTokens(
      accessToken: 'access-2',
      refreshToken: 'refresh-2',
    );

    expect(await manager.getAccessToken(), 'access-2');
    verify(
      () => storage.saveTokens(
        accessToken: 'access-1',
        refreshToken: 'refresh-1',
      ),
    ).called(1);
    verify(
      () => storage.saveTokens(
        accessToken: 'access-2',
        refreshToken: 'refresh-2',
      ),
    ).called(1);
  });

  test('clearSession invalidates the hot token and is idempotent', () async {
    final storage = _MockAuthLocalStorage();
    when(
      () => storage.saveTokens(
        accessToken: any(named: 'accessToken'),
        refreshToken: any(named: 'refreshToken'),
      ),
    ).thenAnswer((_) async {});
    when(() => storage.clear()).thenAnswer((_) async {});
    final manager = AuthTokenManager(storage: storage);

    await manager.installSession(
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
    );
    await manager.clearSession();
    await manager.clearSession();

    expect(await manager.getAccessToken(), isNull);
    verify(() => storage.clear()).called(1);
  });

  test('cleanup wins over a refresh that completes concurrently', () async {
    final storage = _MockAuthLocalStorage();
    final refreshStarted = Completer<void>();
    final releaseRefresh = Completer<void>();
    when(() => storage.getRefreshToken()).thenAnswer((_) async => 'refresh-1');
    when(
      () => storage.saveTokens(
        accessToken: any(named: 'accessToken'),
        refreshToken: any(named: 'refreshToken'),
      ),
    ).thenAnswer((_) async {});
    when(() => storage.clear()).thenAnswer((_) async {});
    final manager = AuthTokenManager(storage: storage);

    final refresh = manager.refresh((_) async {
      refreshStarted.complete();
      await releaseRefresh.future;
      return (accessToken: 'access-2', refreshToken: 'refresh-2');
    });
    await refreshStarted.future;
    final clear = manager.clearSession();

    releaseRefresh.complete();
    await Future.wait([refresh, clear]);

    expect(await manager.getAccessToken(), isNull);
    verify(() => storage.clear()).called(1);
  });

  test(
    'a late initial storage read cannot overwrite an installed session',
    () async {
      final storage = _MockAuthLocalStorage();
      final loadStarted = Completer<void>();
      final releaseLoad = Completer<void>();
      when(() => storage.getAccessToken()).thenAnswer((_) async {
        loadStarted.complete();
        await releaseLoad.future;
        return 'stale-access';
      });
      when(
        () => storage.saveTokens(
          accessToken: any(named: 'accessToken'),
          refreshToken: any(named: 'refreshToken'),
        ),
      ).thenAnswer((_) async {});
      final manager = AuthTokenManager(storage: storage);

      final initialLoad = manager.getAccessToken();
      await loadStarted.future;
      await manager.installSession(
        accessToken: 'fresh-access',
        refreshToken: 'fresh-refresh',
      );

      releaseLoad.complete();
      await initialLoad;

      expect(await manager.getAccessToken(), 'fresh-access');
    },
  );
}
