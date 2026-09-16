import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  test('saves the access and refresh tokens as one record', () async {
    final secureStorage = _MockSecureStorage();
    when(
      () => secureStorage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => secureStorage.delete(key: any(named: 'key')),
    ).thenAnswer((_) async {});
    final storage = AuthLocalStorage(storage: secureStorage);

    await storage.saveTokens(accessToken: 'access', refreshToken: 'refresh');

    verify(
      () => secureStorage.write(
        key: 'auth_token_pair',
        value: jsonEncode({
          'access_token': 'access',
          'refresh_token': 'refresh',
        }),
      ),
    ).called(1);
    verify(() => secureStorage.delete(key: 'access_token')).called(1);
    verify(() => secureStorage.delete(key: 'refresh_token')).called(1);
  });

  test(
    'does not delete legacy credentials when the pair write fails',
    () async {
      final secureStorage = _MockSecureStorage();
      when(
        () => secureStorage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenThrow(StateError('secure storage unavailable'));
      final storage = AuthLocalStorage(storage: secureStorage);

      await expectLater(
        () =>
            storage.saveTokens(accessToken: 'access', refreshToken: 'refresh'),
        throwsStateError,
      );
      verifyNever(() => secureStorage.delete(key: 'access_token'));
      verifyNever(() => secureStorage.delete(key: 'refresh_token'));
    },
  );

  test(
    'rejects an incomplete token pair before writing secure storage',
    () async {
      final secureStorage = _MockSecureStorage();
      final storage = AuthLocalStorage(storage: secureStorage);

      await expectLater(
        () => storage.saveTokens(accessToken: 'access', refreshToken: ''),
        throwsArgumentError,
      );
      verifyNever(
        () => secureStorage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      );
    },
  );

  test('reads legacy token keys until the pair has been migrated', () async {
    final secureStorage = _MockSecureStorage();
    when(() => secureStorage.read(key: any(named: 'key'))).thenAnswer((
      invocation,
    ) async {
      return switch (invocation.namedArguments[#key]) {
        'access_token' => 'legacy-access',
        'refresh_token' => 'legacy-refresh',
        _ => null,
      };
    });
    final storage = AuthLocalStorage(storage: secureStorage);

    expect(await storage.getAccessToken(), 'legacy-access');
    expect(await storage.getRefreshToken(), 'legacy-refresh');
  });

  test(
    'does not fall back to legacy keys when the new pair is incomplete',
    () async {
      final secureStorage = _MockSecureStorage();
      when(() => secureStorage.read(key: any(named: 'key'))).thenAnswer((
        invocation,
      ) async {
        return switch (invocation.namedArguments[#key]) {
          'auth_token_pair' => jsonEncode({'access_token': 'partial-access'}),
          'access_token' => 'legacy-access',
          'refresh_token' => 'legacy-refresh',
          _ => null,
        };
      });
      final storage = AuthLocalStorage(storage: secureStorage);

      expect(await storage.getAccessToken(), isNull);
      expect(await storage.getRefreshToken(), isNull);
      verifyNever(() => secureStorage.read(key: 'access_token'));
      verifyNever(() => secureStorage.read(key: 'refresh_token'));
    },
  );

  test('treats malformed JSON in the new pair as invalid', () async {
    final secureStorage = _MockSecureStorage();
    when(() => secureStorage.read(key: any(named: 'key'))).thenAnswer((
      invocation,
    ) async {
      return switch (invocation.namedArguments[#key]) {
        'auth_token_pair' => '{not-json',
        'access_token' => 'legacy-access',
        'refresh_token' => 'legacy-refresh',
        _ => null,
      };
    });
    final storage = AuthLocalStorage(storage: secureStorage);

    expect(await storage.getAccessToken(), isNull);
    expect(await storage.getRefreshToken(), isNull);
    verify(() => secureStorage.read(key: 'auth_token_pair')).called(1);
    verifyNever(() => secureStorage.read(key: 'access_token'));
    verifyNever(() => secureStorage.read(key: 'refresh_token'));
  });

  test('reads the new token pair once for both token accessors', () async {
    final secureStorage = _MockSecureStorage();
    var pairReads = 0;
    when(() => secureStorage.read(key: any(named: 'key'))).thenAnswer((
      invocation,
    ) async {
      if (invocation.namedArguments[#key] == 'auth_token_pair') {
        pairReads++;
        return jsonEncode({
          'access_token': 'access',
          'refresh_token': 'refresh',
        });
      }
      return null;
    });
    final storage = AuthLocalStorage(storage: secureStorage);

    expect(await storage.getAccessToken(), 'access');
    expect(await storage.getRefreshToken(), 'refresh');
    expect(pairReads, 1);
  });

  test('clear removes the new and legacy credential records', () async {
    final secureStorage = _MockSecureStorage();
    when(
      () => secureStorage.delete(key: any(named: 'key')),
    ).thenAnswer((_) async {});
    final storage = AuthLocalStorage(storage: secureStorage);

    await storage.clear();

    verify(() => secureStorage.delete(key: 'auth_token_pair')).called(1);
    verify(() => secureStorage.delete(key: 'access_token')).called(1);
    verify(() => secureStorage.delete(key: 'refresh_token')).called(1);
  });
}
