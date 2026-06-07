import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/constants/app_constants.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';
import 'package:supanotes/features/tasks/data/local/tasks_local_repository.dart';

class InboxState {
  final NoteModel? inboxNote;
  final bool isSaving;
  final bool hasContent;
  final SaveState saveState;

  const InboxState({
    this.inboxNote,
    this.isSaving = false,
    this.hasContent = false,
    this.saveState = SaveState.idle,
  });

  InboxState copyWith({
    NoteModel? inboxNote,
    bool? isSaving,
    bool? hasContent,
    SaveState? saveState,
  }) =>
      InboxState(
        inboxNote: inboxNote ?? this.inboxNote,
        isSaving: isSaving ?? this.isSaving,
        hasContent: hasContent ?? this.hasContent,
        saveState: saveState ?? this.saveState,
      );
}

final inboxControllerProvider =
    AsyncNotifierProvider<InboxController, InboxState>(
  InboxController.new,
);

class InboxController extends AsyncNotifier<InboxState> {
  Timer? _debounceTimer;

  @override
  Future<InboxState> build() async {
    ref.onDispose(() {
      _debounceTimer?.cancel();
    });
    final inbox = await ref.read(notesRepositoryProvider).watchInbox().first;
    return InboxState(
      inboxNote: inbox,
      hasContent: (inbox?.content.length ?? 0) > 0,
    );
  }

  Future<void> loadOrCreateInbox() async {
    final repo = ref.read(notesRepositoryProvider);
    final inbox = await repo.watchInbox().first;
    state = AsyncValue.data(
      InboxState(
        inboxNote: inbox,
        hasContent: (inbox?.content.length ?? 0) > 0,
      ),
    );
  }

  void autoSave(String noteId, String markdown, List<TaskEntry> tasks) {
    _debounceTimer?.cancel();
    _setSaveState(SaveState.saving);
    _debounceTimer = Timer(
      const Duration(milliseconds: AppConstants.autoSaveDebounceMs),
      () => _flushSave(noteId, markdown, tasks),
    );
  }

  Future<void> flushSave(
    String noteId,
    String markdown,
    List<TaskEntry> tasks,
  ) async {
    _debounceTimer?.cancel();
    await _flushSave(noteId, markdown, tasks);
  }

  Future<void> _flushSave(
    String noteId,
    String markdown,
    List<TaskEntry> tasks,
  ) async {
    try {
      await syncTasks(noteId, tasks);
      await ref
          .read(notesRepositoryProvider)
          .updateNote(noteId, content: markdown);
      _setSaveState(SaveState.saved);
    } catch (_) {
      _setSaveState(SaveState.error);
    }
  }

  Future<void> syncTasks(String noteId, List<TaskEntry> tasks) async {
    final tasksRepo = ref.read(tasksLocalRepositoryProvider);
    final currentTasks = await tasksRepo.watchNoteTasks(noteId).first;
    final currentIds = currentTasks.map((t) => t.id).toSet();
    final docIds = tasks.map((t) => t.id).toSet();

    for (final task in tasks) {
      if (currentIds.contains(task.id)) {
        await tasksRepo.updateTask(TasksCompanion(
          id: Value(task.id),
          title: Value(task.text),
          status: Value(task.isComplete ? 'completed' : 'pending'),
        ));
      } else {
        await tasksRepo.createTask(
          id: task.id,
          noteId: noteId,
          title: task.text,
          position: 0,
          status: task.isComplete ? 'completed' : 'pending',
        );
      }
    }

    final removed = currentIds.difference(docIds);
    for (final id in removed) {
      await tasksRepo.deleteTask(id);
    }
  }

  void updateHasContent(bool hasContent) {
    if (state.hasValue) {
      state = AsyncValue.data(state.value!.copyWith(hasContent: hasContent));
    }
  }

  void _setSaveState(SaveState saveState) {
    if (state.hasValue) {
      state = AsyncValue.data(state.value!.copyWith(saveState: saveState));
    }
  }
}
