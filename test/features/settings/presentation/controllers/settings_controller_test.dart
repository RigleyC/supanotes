import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';
import 'package:supanotes/features/auth/data/session_cache.dart';
import 'package:supanotes/features/settings/data/settings_repository.dart';
import 'package:supanotes/features/settings/data/settings_models.dart';
import 'package:supanotes/features/settings/presentation/controllers/settings_controller.dart';

class _MockAuthLocalStorage extends Mock implements AuthLocalStorage {}

class _MockSettingsRepository extends Mock implements ISettingsRepository {}

final _epoch = DateTime.utc(2024);

void main() {
  group('settingsProvider', () {
    ProviderContainer _makeContainer({Map<String, dynamic>? settings}) {
      final storage = _MockAuthLocalStorage();
      when(() => storage.getAccessToken()).thenAnswer((_) async => null);
      when(() => storage.getRefreshToken()).thenAnswer((_) async => null);
      when(() => storage.getSessionData()).thenAnswer((_) async => const {});
      when(() => storage.saveSessionData(any())).thenAnswer((_) async {});
      when(() => storage.saveTokens(
            accessToken: any(named: 'accessToken'),
            refreshToken: any(named: 'refreshToken'),
          )).thenAnswer((_) async {});
      final repo = _MockSettingsRepository();
      when(() => repo.getSettings())
          .thenAnswer((_) async => UserSettings(
                timezone: 'America/Sao_Paulo',
                createdAt: _epoch,
                updatedAt: _epoch,
              ));
      return ProviderContainer(
        overrides: [
          authLocalStorageProvider.overrideWithValue(storage),
          sessionCacheProvider.overrideWith(() => SessionCacheNotifier()),
          settingsRepositoryProvider.overrideWithValue(repo),
        ],
      );
    }

    test('returns default timezone from cache', () async {
      final container = _makeContainer();
      await container.read(sessionCacheProvider.notifier).hydrate({
        'settings': {'timezone': 'America/Sao_Paulo'},
      });
      addTearDown(container.dispose);
      final state = await container.read(settingsProvider.future);
      expect(state.timezone, 'America/Sao_Paulo');
    });

    test('reads settings from repository when cache is empty', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final state = await container.read(settingsProvider.future);
      expect(state.timezone, 'America/Sao_Paulo');
    });
  });
}
