import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/features/auth/data/session_cache.dart';
import 'package:supanotes/features/settings/data/settings_repository.dart';

/// Typed, reactive access to the user's preferences.
///
/// Derives `isGridView` from the raw `sessionCacheProvider` so the UI never
/// touches `Map<String, dynamic>` directly.
final isGridViewProvider = Provider.autoDispose<bool>((ref) {
  final settings = ref.watch(sessionCacheProvider).settings;
  final prefs = settings['preferences'] as Map<String, dynamic>? ?? {};
  return prefs['notes_view_mode'] == 'grid';
});

/// Orchestrates preference mutations with optimistic local updates and
/// automatic rollback on server failure.
final preferencesControllerProvider =
    NotifierProvider.autoDispose<PreferencesController, void>(
      PreferencesController.new,
    );

class PreferencesController extends Notifier<void> {
  @override
  void build() {}

  /// Toggles the notes view mode between list and grid.
  ///
  /// Updates the local [SessionCache] optimistically *before* the HTTP call
  /// so the UI feels instant. If the server write fails, the cache is
  /// rolled back to the previous state.
  Future<void> toggleNotesViewMode() async {
    final cache = ref.read(sessionCacheProvider);
    final currentPrefs = Map<String, dynamic>.from(
      (cache.settings['preferences'] as Map<String, dynamic>?) ?? {},
    );
    final currentMode = currentPrefs['notes_view_mode'] as String? ?? 'list';
    final newMode = currentMode == 'grid' ? 'list' : 'grid';
    currentPrefs['notes_view_mode'] = newMode;

    final oldSettings = Map<String, dynamic>.from(cache.settings);

    final updatedSettings = Map<String, dynamic>.from(cache.settings);
    updatedSettings['preferences'] = currentPrefs;
    await ref
        .read(sessionCacheProvider.notifier)
        .updateSettings(updatedSettings);

    try {
      await ref
          .read(settingsRepositoryProvider)
          .updateSettings(preferences: currentPrefs);
    } catch (e) {
      await ref.read(sessionCacheProvider.notifier).updateSettings(oldSettings);
      rethrow;
    }
  }
}
