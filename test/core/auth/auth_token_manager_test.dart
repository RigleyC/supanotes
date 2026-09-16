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
      when(storage.getAccessToken).thenAnswer((_) async => 'access-1');
      when(storage.getRefreshToken).thenAnswer((_) async => 'refresh-1');
      final manager = AuthTokenManager(storage: storage);

      expect(await manager.getAccessToken(), 'access-1');
      expect(await manager.getAccessToken(), 'access-1');
      verify(storage.getAccessToken).called(1);
    },
  );

  test('install and refresh update storage and the in-memory pair', () async {
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
    final refreshed = await manager.refresh((refreshToken) async {
      expect(refreshToken, 'refresh-1');
      return (accessToken: 'access-2', refreshToken: 'refresh-2');
    });

    expect(refreshed?.accessToken, 'access-2');
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

  test('does not call refresh transport when the token is empty', () async {
    final storage = _MockAuthLocalStorage();
    when(storage.getAccessToken).thenAnswer((_) async => null);
    when(storage.getRefreshToken).thenAnswer((_) async => '');
    final manager = AuthTokenManager(storage: storage);
    var transportCalled = false;

    final result = await manager.refresh((_) async {
      transportCalled = true;
      return (accessToken: 'access-2', refreshToken: 'refresh-2');
    });

    expect(result, isNull);
    expect(transportCalled, isFalse);
  });

  test(
    'keeps an access token available while a partial session is detected',
    () async {
      final storage = _MockAuthLocalStorage();
      when(storage.getAccessToken).thenAnswer((_) async => 'access-only');
      when(storage.getRefreshToken).thenAnswer((_) async => null);
      final manager = AuthTokenManager(storage: storage);

      expect(await manager.getAccessToken(), 'access-only');
      expect(await manager.hasCompleteSession(), isFalse);
    },
  );

  test('clearSession invalidates the hot token and is idempotent', () async {
    final storage = _MockAuthLocalStorage();
    when(storage.getAccessToken).thenAnswer((_) async => null);
    when(
      () => storage.saveTokens(
        accessToken: any(named: 'accessToken'),
        refreshToken: any(named: 'refreshToken'),
      ),
    ).thenAnswer((_) async {});
    when(storage.clear).thenAnswer((_) async {});
    final manager = AuthTokenManager(storage: storage);

    await manager.installSession(
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
    );
    await manager.clearSession();
    await manager.clearSession();

    expect(await manager.getAccessToken(), isNull);
    verify(storage.clear).called(1);
  });

  test('cleanup wins over a refresh that completes concurrently', () async {
    final storage = _MockAuthLocalStorage();
    final refreshStarted = Completer<void>();
    final releaseRefresh = Completer<void>();
    when(storage.getAccessToken).thenAnswer((_) async => 'access-1');
    when(storage.getRefreshToken).thenAnswer((_) async => 'refresh-1');
    when(
      () => storage.saveTokens(
        accessToken: any(named: 'accessToken'),
        refreshToken: any(named: 'refreshToken'),
      ),
    ).thenAnswer((_) async {});
    when(storage.clear).thenAnswer((_) async {});
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
    verify(storage.clear).called(1);
  });

  test(
    'refresh-token reads wait for an in-flight refresh replacement',
    () async {
      final storage = _MockAuthLocalStorage();
      final refreshStarted = Completer<void>();
      final releaseRefresh = Completer<void>();
      var refreshTokenReads = 0;
      when(storage.getAccessToken).thenAnswer((_) async => 'access-1');
      when(storage.getRefreshToken).thenAnswer((_) async {
        refreshTokenReads++;
        return refreshTokenReads == 1 ? 'refresh-1' : 'refresh-2';
      });
      when(
        () => storage.saveTokens(
          accessToken: any(named: 'accessToken'),
          refreshToken: any(named: 'refreshToken'),
        ),
      ).thenAnswer((_) async {});
      final manager = AuthTokenManager(storage: storage);

      final refresh = manager.refresh((_) async {
        refreshStarted.complete();
        await releaseRefresh.future;
        return (accessToken: 'access-2', refreshToken: 'refresh-2');
      });
      await refreshStarted.future;

      final logoutToken = manager.getRefreshToken();
      releaseRefresh.complete();

      await refresh;
      expect(await logoutToken, 'refresh-2');
    },
  );

  test('keeps the session lock during the logout operation', () async {
    final storage = _MockAuthLocalStorage();
    final logoutStarted = Completer<void>();
    final releaseLogout = Completer<void>();
    var refreshStarted = false;
    when(storage.getAccessToken).thenAnswer((_) async => 'access-1');
    when(storage.getRefreshToken).thenAnswer((_) async => 'refresh-1');
    when(
      () => storage.saveTokens(
        accessToken: any(named: 'accessToken'),
        refreshToken: any(named: 'refreshToken'),
      ),
    ).thenAnswer((_) async {});
    final manager = AuthTokenManager(storage: storage);

    final logout = manager.withSessionLock((refreshToken) async {
      expect(refreshToken, 'refresh-1');
      logoutStarted.complete();
      await releaseLogout.future;
    });
    await logoutStarted.future;

    final refresh = manager.refresh((_) async {
      refreshStarted = true;
      return (accessToken: 'access-2', refreshToken: 'refresh-2');
    });
    await Future<void>.delayed(Duration.zero);
    expect(refreshStarted, isFalse);

    releaseLogout.complete();
    await Future.wait([logout, refresh]);
    expect(refreshStarted, isTrue);
  });

  test(
    'a late initial storage read cannot overwrite an installed session',
    () async {
      final storage = _MockAuthLocalStorage();
      final loadStarted = Completer<void>();
      final releaseLoad = Completer<void>();
      when(storage.getAccessToken).thenAnswer((_) async {
        loadStarted.complete();
        await releaseLoad.future;
        return 'stale-access';
      });
      when(storage.getRefreshToken).thenAnswer((_) async => 'stale-refresh');
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
