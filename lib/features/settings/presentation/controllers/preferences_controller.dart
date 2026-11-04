import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/features/auth/data/session_cache.dart';
import 'package:supanotes/features/settings/data/settings_repository.dart';
import 'package:supanotes/features/tasks/application/task_source_preference.dart';

/// Typed, reactive access to the user's preferences.
///
/// Derives `isGridView` from the raw `sessionCacheProvider` so the UI never
/// touches `Map<String, dynamic>` directly.
final Provider<bool> isGridViewProvider = Provider.autoDispose<bool>((ref) {
  final settings = ref.watch(sessionCacheProvider).settings;
  final prefs = settings['preferences'] as Map<String, dynamic>? ?? {};
  return prefs['notes_view_mode'] == 'grid';
});

/// Orchestrates preference mutations with optimistic local updates and
/// automatic rollback on server failure.
final preferencesControllerProvider =
    NotifierProvider<PreferencesController, void>(
      PreferencesController.new,
    );

class PreferencesController extends Notifier<void> {
  @override
  void build() {}

  Map<String, dynamic> get _preferences => Map<String, dynamic>.from(
    (ref.read(sessionCacheProvider).settings['preferences']
            as Map<String, dynamic>?) ??
        const {},
  );

  /// Toggles the notes view mode between list and grid.
  Future<void> toggleNotesViewMode() {
    final currentMode = _preferences['notes_view_mode'] as String? ?? 'list';
    return _set('notes_view_mode', currentMode == 'grid' ? 'list' : 'grid');
  }

  /// Shows or hides the tasks written inside notes in the Tasks list.
  Future<void> setIncludeNoteTasks(bool value) =>
      _set(includeNoteTasksPreferenceKey, value);

  /// Replaces the cached preferences with the server's, so a choice made on
  /// another device shows up here.
  Future<void> refresh() async {
    final remote = await ref.read(settingsRepositoryProvider).getSettings();
    final cache = ref.read(sessionCacheProvider);
    await ref.read(sessionCacheProvider.notifier).updateSettings({
      ...cache.settings,
      'preferences': remote.preferences,
    });
  }

  /// Sets [key] to [value].
  ///
  /// Updates the local [SessionCache] optimistically *before* the HTTP call
  /// so the UI feels instant. If the server write fails, the cache is
  /// rolled back to the previous state.
  Future<void> _set(String key, Object value) async {
    final currentPrefs = _preferences;
    if (currentPrefs[key] == value) return;
    currentPrefs[key] = value;

    final cache = ref.read(sessionCacheProvider);
    final oldSettings = Map<String, dynamic>.from(cache.settings);
    await ref.read(sessionCacheProvider.notifier).updateSettings({
      ...cache.settings,
      'preferences': currentPrefs,
    });

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
