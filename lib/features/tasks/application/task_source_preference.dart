import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/di/providers.dart';

/// Whether the Tasks list also shows the tasks written inside notes.
///
/// Saved on the device, so the choice survives leaving the screen and
/// restarting the app. Shown by default.
final includeNoteTasksProvider =
    NotifierProvider<IncludeNoteTasksPreference, bool>(
      IncludeNoteTasksPreference.new,
    );

class IncludeNoteTasksPreference extends Notifier<bool> {
  static const storageKey = 'tasks.include_note_tasks';

  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(storageKey) ?? true;

  /// Shows or hides note tasks and remembers the choice.
  void set(bool value) {
    if (state == value) return;
    state = value;
    unawaited(ref.read(sharedPreferencesProvider).setBool(storageKey, value));
  }
}
