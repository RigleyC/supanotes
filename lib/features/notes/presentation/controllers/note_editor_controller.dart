import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/constants/app_constants.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/tasks/data/local/tasks_local_repository.dart';

enum SaveState { idle, saving, saved, error }

class TaskEntry {
  final String id;
  final String text;
  final bool isComplete;

  const TaskEntry({
    required this.id,
    required this.text,
    required this.isComplete,
  });
}

class NoteEditorState {
  final NoteModel? note;
  final bool isSaving;
  final DateTime? lastSavedAt;
  final SaveState saveState;

  const NoteEditorState({
    this.note,
    this.isSaving = false,
    this.lastSavedAt,
    this.saveState = SaveState.idle,
  });

  NoteEditorState copyWith({
    NoteModel? note,
    bool? isSaving,
    DateTime? lastSavedAt,
    SaveState? saveState,
  }) =>
      NoteEditorState(
        note: note ?? this.note,
        isSaving: isSaving ?? this.isSaving,
        lastSavedAt: lastSavedAt ?? this.lastSavedAt,
        saveState: saveState ?? this.saveState,
      );
}

final noteEditorControllerProvider =
    AsyncNotifierProvider<NoteEditorController, NoteEditorState>(
  NoteEditorController.new,
);

class NoteEditorController extends AsyncNotifier<NoteEditorState> {
  Timer? _saveDebounce;
  Timer? _titleDebounce;

  @override
  Future<NoteEditorState> build() async {
    ref.onDispose(() {
      _saveDebounce?.cancel();
      _titleDebounce?.cancel();
    });
    return const NoteEditorState();
  }

  Future<void> loadNote(String noteId) async {
    final repo = ref.read(notesRepositoryProvider);
    final notes = await repo.watchNotes().first;
    final note = notes.where((n) => n.id == noteId).firstOrNull;
    state = AsyncValue.data(state.value!.copyWith(note: note));
  }

  void onContentChanged(
    String noteId,
    String markdown,
    List<TaskEntry> tasks,
  ) {
    _saveDebounce?.cancel();
    _setSaveState(SaveState.saving);
    _saveDebounce = Timer(
      Duration(milliseconds: AppConstants.autoSaveDebounceMs),
      () => _flushContentSave(noteId, markdown, tasks),
    );
  }

  void onTitleChanged(String noteId, String title) {
    _titleDebounce?.cancel();
    _titleDebounce = Timer(
      Duration(milliseconds: AppConstants.autoSaveDebounceMs),
      () => _flushTitleSave(noteId, title),
    );
  }

  Future<void> flushContentSave(
    String noteId,
    String markdown,
    List<TaskEntry> tasks,
  ) async {
    _saveDebounce?.cancel();
    await _flushContentSave(noteId, markdown, tasks);
  }

  Future<void> flushTitleSave(String noteId, String title) async {
    _titleDebounce?.cancel();
    await _flushTitleSave(noteId, title);
  }

  Future<void> toggleFavorite(String noteId) async {
    final current = state.value!;
    final note = current.note;
    if (note == null) return;

    state = AsyncValue.data(
      current.copyWith(
        note: note.copyWith(favorite: !note.favorite),
      ),
    );

    try {
      await ref.read(notesRepositoryProvider).toggleFavorite(noteId);
    } catch (_) {
      state = AsyncValue.data(current.copyWith(note: note));
    }
  }

  Future<void> _flushContentSave(
    String noteId,
    String markdown,
    List<TaskEntry> tasks,
  ) async {
    try {
      await _syncTasks(noteId, tasks);
      await ref
          .read(notesRepositoryProvider)
          .updateNote(noteId, content: markdown);
      _setSaveState(SaveState.saved);
    } catch (_) {
      _setSaveState(SaveState.error);
    }
  }

  Future<void> _flushTitleSave(String noteId, String title) async {
    try {
      await ref.read(notesRepositoryProvider).updateNote(
            noteId,
            title: title.isEmpty ? null : title,
          );
      _setSaveState(SaveState.saved);
    } catch (_) {
      _setSaveState(SaveState.error);
    }
  }

  Future<void> _syncTasks(String noteId, List<TaskEntry> tasks) async {
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

  void _setSaveState(SaveState saveState) {
    if (state.hasValue) {
      state = AsyncValue.data(state.value!.copyWith(saveState: saveState));
    }
  }


}
