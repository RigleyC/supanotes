import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';
import 'package:supanotes/features/auth/data/session_cache.dart';
import 'package:supanotes/features/settings/presentation/controllers/contexts_controller.dart';

class _MockAuthLocalStorage extends Mock implements AuthLocalStorage {}

void main() {
  group('contextsProvider', () {
    ProviderContainer makeContainer() {
      final storage = _MockAuthLocalStorage();
      when(() => storage.getSessionData()).thenAnswer((_) async => const {});
      when(() => storage.saveSessionData(any())).thenAnswer((_) async {});
      return ProviderContainer(
        overrides: [
          authLocalStorageProvider.overrideWithValue(storage),
          sessionCacheProvider.overrideWith(() => SessionCacheNotifier()),
        ],
      );
    }

    test('returns contexts from cache when available', () async {
      final container = makeContainer();
      await container.read(sessionCacheProvider.notifier).hydrate({
        'contexts': [
          {
            'id': 'c-1',
            'slug': 'work',
            'name': 'Work',
            'created_at': '2025-01-01T00:00:00.000Z',
            'updated_at': '2025-06-01T00:00:00.000Z',
          },
        ],
      });
      addTearDown(container.dispose);
      final contexts = await container.read(contextsProvider.future);
      expect(contexts.length, 1);
      expect(contexts.first.name, 'Work');
    });
  });
}
