import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:supanotes/features/auth/data/session_cache.dart';
import 'package:supanotes/features/settings/data/settings_models.dart';
import 'package:supanotes/features/settings/data/settings_repository.dart';

/// A session cache that keeps settings in memory instead of secure storage.
class MemorySessionCache extends SessionCacheNotifier {
  MemorySessionCache([this.initial = const {}]);

  final Map<String, dynamic> initial;

  @override
  SessionCache build() => SessionCache(settings: initial);

  @override
  Future<void> updateSettings(Map<String, dynamic> settings) async {
    state = SessionCache(settings: settings);
  }
}

/// The settings endpoint, backed by a map.
class FakeSettingsRepository implements ISettingsRepository {
  FakeSettingsRepository([Map<String, dynamic>? preferences])
    : preferences = preferences ?? {};

  /// The preferences stored "on the server".
  Map<String, dynamic> preferences;

  /// Makes the next writes fail, like an offline device.
  bool failWrites = false;

  UserSettings get _settings => UserSettings(
    timezone: 'America/Sao_Paulo',
    preferences: Map.of(preferences),
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );

  @override
  Future<UserSettings> getSettings() async => _settings;

  @override
  Future<UserSettings> updateSettings({
    String? timezone,
    Map<String, dynamic>? preferences,
  }) async {
    if (failWrites) throw Exception('offline');
    if (preferences != null) this.preferences = Map.of(preferences);
    return _settings;
  }

  @override
  Future<String> generateMcpToken() => throw UnimplementedError();
}

/// Overrides that make the user's preferences work in widget tests.
List<Override> userPreferencesOverrides(
  FakeSettingsRepository repository, {
  Map<String, dynamic> cachedPreferences = const {},
}) => [
  sessionCacheProvider.overrideWith(
    () => MemorySessionCache({'preferences': cachedPreferences}),
  ),
  settingsRepositoryProvider.overrideWithValue(repository),
];
