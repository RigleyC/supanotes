import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/auth/data/session_cache.dart';
import 'package:supanotes/features/settings/data/settings_repository.dart';

class SettingsState {
  final String timezone;

  const SettingsState({this.timezone = 'UTC'});
}

final settingsProvider = FutureProvider.autoDispose<SettingsState>((ref) async {
  final cache = ref.read(sessionCacheProvider);
  if (cache.settings.isNotEmpty) {
    return SettingsState(
      timezone: cache.settings['timezone'] as String? ?? 'UTC',
    );
  }
  final settings = await ref.read(settingsRepositoryProvider).getSettings();
  return SettingsState(timezone: settings.timezone);
});
