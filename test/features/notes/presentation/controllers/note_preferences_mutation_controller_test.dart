import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/catalog/data/notes_repository.dart';
import 'package:supanotes/features/notes/preferences/data/user_note_preferences_repository.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/catalog/model/note_with_tasks.dart';
import 'package:supanotes/features/notes/preferences/application/note_preferences_mutation_controller.dart';

void main() {
  test(
    'two fast toggles keep the newest value when the older write fails',
    () async {
      final notes = _FakeNotesRepository(_note(hideCompleted: false));
      final preferences = _FakePreferencesRepository(notes);
      final controller = _controller(notes, preferences);
      final firstWrite = Completer<void>();

      preferences.nextHideCompletedWrite = (_) async {
        notes.applyHideCompleted(true);
        await firstWrite.future;
        throw StateError('first failed');
      };

      final first = controller.setHideCompleted(
        current: notes.note,
        value: true,
      );
      await pumpEventQueue();

      expect(notes.note.hideCompleted, isTrue);
      expect(controller.state.status, NotePreferenceMutationStatus.saving);

      final second = controller.setHideCompleted(
        current: notes.note,
        value: false,
      );
      await second;
      expect(notes.note.hideCompleted, isFalse);

      firstWrite.complete();
      await first;

      expect(notes.note.hideCompleted, isFalse);
      expect(controller.state.status, NotePreferenceMutationStatus.idle);
      expect(controller.state.error, isNull);
    },
  );

  test(
    'rollback changes only the failed field and preserves newer fields',
    () async {
      final notes = _FakeNotesRepository(
        _note(hideCompleted: false, collapseImages: false),
      );
      final preferences = _FakePreferencesRepository(notes);
      final controller = _controller(notes, preferences);

      preferences.nextHideCompletedWrite = (_) async {
        notes.applyHideCompleted(true);
        throw StateError('hide failed');
      };

      await controller.setCollapseImages(current: notes.note, value: true);
      await controller.setHideCompleted(current: notes.note, value: true);

      expect(notes.note.hideCompleted, isFalse);
      expect(notes.note.collapseImages, isTrue);
      expect(controller.state.status, NotePreferenceMutationStatus.error);
    },
  );

  test(
    'retry clears the old error and returns to idle after success',
    () async {
      final notes = _FakeNotesRepository(_note(hideCompleted: false));
      final preferences = _FakePreferencesRepository(notes);
      final controller = _controller(notes, preferences);

      preferences.nextHideCompletedWrite = (_) async {
        notes.applyHideCompleted(true);
        throw StateError('temporary failure');
      };

      await controller.setHideCompleted(current: notes.note, value: true);
      expect(controller.state.status, NotePreferenceMutationStatus.error);
      expect(notes.note.hideCompleted, isFalse);

      await controller.setHideCompleted(current: notes.note, value: true);

      expect(notes.note.hideCompleted, isTrue);
      expect(controller.state.status, NotePreferenceMutationStatus.idle);
      expect(controller.state.error, isNull);
    },
  );

  test(
    'concurrent mutations where first fails and second succeeds end with idle status and no error',
    () async {
      final notes = _FakeNotesRepository(
        _note(hideCompleted: false, collapseImages: false),
      );
      final preferences = _FakePreferencesRepository(notes);
      final controller = _controller(notes, preferences);
      final secondWrite = Completer<void>();

      preferences.nextHideCompletedWrite = (_) async {
        throw StateError('hide failed');
      };
      notes.nextUpdateNoteWrite = (_) async {
        await secondWrite.future;
      };

      final op1 = controller.setHideCompleted(current: notes.note, value: true);
      final op2 = controller.setCollapseImages(
        current: notes.note,
        value: true,
      );

      await op1; // op1 fails immediately
      expect(controller.state.status, NotePreferenceMutationStatus.error);
      expect(controller.state.inFlightCount, 1);

      secondWrite.complete();
      await op2; // op2 succeeds after op1 failed

      expect(controller.state.status, NotePreferenceMutationStatus.idle);
      expect(controller.state.error, isNull);
      expect(controller.state.inFlightCount, 0);
    },
  );
}

NotePreferenceMutationController _controller(
  _FakeNotesRepository notes,
  _FakePreferencesRepository preferences,
) {
  return NotePreferenceMutationController(
    userId: 'user-1',
    notesRepository: notes,
    preferencesRepository: preferences,
  );
}

NoteModel _note({bool hideCompleted = false, bool collapseImages = false}) {
  return NoteModel(
    id: 'note-1',
    userId: 'user-1',
    content: '',
    title: 'Note',
    favorite: false,
    archived: false,
    hideCompleted: hideCompleted,
    collapseImages: collapseImages,
    createdAt: DateTime.utc(2026, 7, 26),
    updatedAt: DateTime.utc(2026, 7, 26),
    hasRemoteCopy: true,
  );
}

class _FakePreferencesRepository implements UserNotePreferencesRepository {
  _FakePreferencesRepository(this.notes);

  final _FakeNotesRepository notes;
  Future<void> Function(bool value)? nextHideCompletedWrite;

  @override
  Future<void> setHideCompleted(
    String userId,
    String noteId,
    bool hideCompleted,
  ) async {
    final write = nextHideCompletedWrite;
    nextHideCompletedWrite = null;
    if (write != null) {
      await write(hideCompleted);
      return;
    }
    notes.applyHideCompleted(hideCompleted);
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeNotesRepository implements INotesRepository {
  _FakeNotesRepository(this.note);

  NoteModel note;
  Future<void> Function(bool? collapseImages)? nextUpdateNoteWrite;

  void applyHideCompleted(bool value) {
    note = note.copyWith(hideCompleted: value);
  }

  @override
  Future<void> updateNote(
    String id, {
    String? content,
    bool? collapseImages,
  }) async {
    final write = nextUpdateNoteWrite;
    nextUpdateNoteWrite = null;
    if (write != null) {
      await write(collapseImages);
    }
    if (collapseImages != null) {
      note = note.copyWith(collapseImages: collapseImages);
    }
  }

  @override
  Future<NoteModel?> getNoteById(String id) async =>
      note.id == id ? note : null;

  @override
  Stream<List<NoteModel>> watchNotes({bool favoritesOnly = false}) {
    return Stream.value([note]);
  }

  @override
  Stream<NoteModel?> watchNoteById(String id) {
    return Stream.value(note.id == id ? note : null);
  }

  @override
  Stream<NoteWithTasks> watchNoteWithTasks(String noteId) {
    return Stream.value(NoteWithTasks(note: note, tasks: const []));
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
