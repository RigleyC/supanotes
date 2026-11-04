import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/auth/data/session_cache.dart';

/// Key of the "show tasks written inside notes" choice in the user's
/// preferences.
const includeNoteTasksPreferenceKey = 'tasks_include_note_tasks';

/// Whether the Tasks list also shows the tasks written inside notes.
///
/// Part of the user's preferences, which are stored on the server, so the
/// choice follows the account across devices. Shown by default.
final includeNoteTasksProvider = Provider.autoDispose<bool>((ref) {
  final settings = ref.watch(sessionCacheProvider).settings;
  final prefs = settings['preferences'] as Map<String, dynamic>? ?? const {};
  return prefs[includeNoteTasksPreferenceKey] as bool? ?? true;
});
