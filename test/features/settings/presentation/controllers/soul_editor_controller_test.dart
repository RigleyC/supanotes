import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';
import 'package:supanotes/features/auth/data/session_cache.dart';
import 'package:supanotes/features/settings/data/settings_models.dart';
import 'package:supanotes/features/settings/data/settings_repository.dart';
import 'package:supanotes/features/settings/presentation/controllers/soul_editor_controller.dart';

class _MockAuthLocalStorage extends Mock implements AuthLocalStorage {}

class _FakeSettingsRepository implements ISettingsRepository {
  var soul = const Soul(personality: 'fresh soul');
  var getSoulCalls = 0;

  @override
  Future<Soul> getSoul() async {
    getSoulCalls++;
    return soul;
  }

  @override
  Future<Soul> updateSoul(String personality) async {
    soul = Soul(personality: personality);
    return soul;
  }

  @override
  Future<UserSettings> getSettings() => throw UnimplementedError();

  @override
  Future<UserSettings> updateSettings(String timezone) =>
      throw UnimplementedError();

  @override
  Future<List<UserContext>> getContexts() => throw UnimplementedError();

  @override
  Future<UserContext> createContext(String name) => throw UnimplementedError();

  @override
  Future<void> deleteContext(String id) => throw UnimplementedError();
}

void main() {
  ProviderContainer makeContainer(_FakeSettingsRepository repo) {
    final storage = _MockAuthLocalStorage();
    when(() => storage.getSessionData()).thenAnswer((_) async => const {});
    when(() => storage.saveSessionData(any())).thenAnswer((_) async {});

    return ProviderContainer(
      overrides: [
        authLocalStorageProvider.overrideWithValue(storage),
        sessionCacheProvider.overrideWith(() => SessionCacheNotifier()),
        settingsRepositoryProvider.overrideWithValue(repo),
      ],
    );
  }

  test('reads updated soul from session cache after save', () async {
    final repo = _FakeSettingsRepository();
    final container = makeContainer(repo);
    addTearDown(container.dispose);

    await container.read(sessionCacheProvider.notifier).hydrate({
      'soul': {'personality': 'cached soul'},
    });

    final first = await container.read(soulProvider.future);
    expect(first.personality, 'cached soul');

    await container.read(sessionCacheProvider.notifier).updateSoul({
      'personality': 'fresh soul',
    });
    container.invalidate(soulProvider);

    final second = await container.read(soulProvider.future);
    expect(second.personality, 'fresh soul');
    expect(repo.getSoulCalls, 0);
  });
}
